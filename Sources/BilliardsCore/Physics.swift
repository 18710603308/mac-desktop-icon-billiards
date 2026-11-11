import Foundation

public struct V2: Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static func + (a: V2, b: V2) -> V2 { V2(a.x + b.x, a.y + b.y) }
    public static func - (a: V2, b: V2) -> V2 { V2(a.x - b.x, a.y - b.y) }
    public static func * (a: V2, s: Double) -> V2 { V2(a.x * s, a.y * s) }
    public var length: Double { (x * x + y * y).squareRoot() }
    public func distance(to o: V2) -> Double { (self - o).length }
}

public struct TableRect {
    public var left: Double, top: Double, right: Double, bottom: Double
    public init(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
    public var width: Double { right - left }
    public var height: Double { bottom - top }
}

public final class Body {
    public var x: Double, y: Double
    public var radius: Double
    public var vx = 0.0, vy = 0.0
    public var angle = 0.0, impact = 0.0
    public init(x: Double, y: Double, radius: Double) {
        self.x = x; self.y = y; self.radius = radius
    }
    public var position: V2 { V2(x, y) }
    public var speed: Double { (vx * vx + vy * vy).squareRoot() }
}

public enum GameState: Equatable {
    case ready, stroke, rolling, returnWhite, ballInHand, finished
}

public enum GuideRole { case incoming, white, target }

public struct GuideLine {
    public let role: GuideRole
    public let start: V2
    public let end: V2
}

public struct Pose {
    public var x: Double, y: Double, width: Double, height: Double, angle: Double
}

/// Billiards physics for desktop icons, in desktop pixels (y grows downwards).
/// Port of the Windows edition's `dib/table.py`; constants and behaviour match.
public final class BilliardsMotion {
    public static let exitSeconds = 0.72
    public static let minShotCharge = 0.18
    public static let railRebound = 0.88
    public static let ballImpulse = 0.96
    public static let rollingDrag = 0.45
    public static let stopSpeed = 0.008

    public let sizes: [V2]
    public let workArea: TableRect
    public let bounds: TableRect
    public let pockets: [V2]
    public let pocketRadius: Double
    public let tile: Double
    public let radius: Double
    public let whiteRadius: Double
    public let rack: [V2]

    private var whiteBody = Body(x: 0, y: 0, radius: 1)
    public var white: Body { whiteBody }
    public private(set) var icons: [Body] = []
    public private(set) var bodies: [Body] = []
    public private(set) var sunk: Set<Int> = []
    public private(set) var whiteSunk = false
    public private(set) var state: GameState = .ready
    public private(set) var charge = 0.0
    public private(set) var power = 0.0
    public private(set) var roundSeconds = 0
    public private(set) var poses: [Pose] = []
    public var aim = V2(1, 0)

    private var exits: [Int: (x: Double, y: Double, tx: Double, ty: Double, age: Double)] = [:]
    private var readyFor = 0.0
    private var stroke = 0.0
    private var roundStartedAt: Double?
    private var breakShot = true

    public init(workArea: TableRect, sizes: [V2]) {
        self.sizes = sizes
        self.workArea = workArea
        let width = workArea.width, height = workArea.height
        bounds = TableRect((workArea.left + width * 0.06).rounded(),
                           (workArea.top + height * 0.09).rounded(),
                           (workArea.right - width * 0.06).rounded(),
                           (workArea.bottom - height * 0.09).rounded())
        let left = bounds.left, top = bounds.top, right = bounds.right, bottom = bounds.bottom
        let mid = (left + right) / 2
        pockets = [V2(left, top), V2(mid, top), V2(right, top),
                   V2(left, bottom), V2(mid, bottom), V2(right, bottom)]
        pocketRadius = min(49, max(18, bounds.height * 0.047))
        let count = sizes.count
        let root: Double = (8.0 * Double(count) + 1.0).squareRoot()
        let columns: Int = max(1, Int(((root - 1.0) / 2.0).rounded(.up)))
        let pitchByWidth: Double = bounds.width * 0.45 / (Double(columns) + 0.5)
        let pitchByHeight: Double = bounds.height * 0.79 / Double(columns)
        let pitch: Double = min(94.0, min(pitchByWidth, pitchByHeight))
        tile = min(64, pitch * 0.70)
        radius = pitch * 0.46
        whiteRadius = min(25, radius * 0.9)
        var rack: [V2] = []
        let midY: Double = (top + bottom) / 2
        for column in 0..<columns {
            let depth = min(column + 1, count - rack.count)
            for i in 0..<depth {
                let x: Double = left + bounds.width * 0.52 + Double(column) * pitch * 0.84
                let offset: Double = (Double(i) - Double(depth - 1) / 2.0) * pitch * 0.95
                rack.append(V2(x, midY + offset))
            }
        }
        self.rack = rack
        reset()
    }

    public func reset() {
        whiteBody = Body(x: bounds.left + bounds.width * 0.20,
                         y: (bounds.top + bounds.bottom) / 2, radius: whiteRadius)
        icons = rack.map { Body(x: $0.x, y: $0.y, radius: radius) }
        bodies = [white] + icons
        sunk = []
        whiteSunk = false
        exits = [:]
        state = .ready
        readyFor = 0
        roundStartedAt = nil
        roundSeconds = 0
        stroke = 0
        power = 0
        charge = 0
        breakShot = true
        aim = defaultAim()
        poses = computePoses()
    }

    public var pocketedIcons: Int { sunk.count - (sunk.contains(0) ? 1 : 0) }

    public func activeBodies() -> [Body] {
        bodies.enumerated().filter { !sunk.contains($0.offset) }.map(\.element)
    }

    private func activeIcons() -> [Body] {
        icons.enumerated().filter { !sunk.contains($0.offset + 1) }.map(\.element)
    }

    private func defaultAim() -> V2 {
        let targets = activeIcons()
        guard let target = targets.min(by: {
            $0.position.distance(to: white.position) < $1.position.distance(to: white.position)
        }) else { return V2(1, 0) }
        if breakShot { return V2(1, 0.022) }
        let shot = pocketShot(targets)
        let d = shot.map { $0 - white.position } ?? (target.position - white.position)
        let length = max(1, d.length)
        return V2(d.x / length, d.y / length)
    }

    private static func clear(_ from: V2, _ to: V2, others: [Body], radius: Double) -> Bool {
        let d = to - from
        let length = d.x * d.x + d.y * d.y
        for other in others {
            let o = other.position - from
            let t = max(0, min(1, (o.x * d.x + o.y * d.y) / max(1, length)))
            if V2(o.x - t * d.x, o.y - t * d.y).length < other.radius + radius { return false }
        }
        return true
    }

    private func pocketShot(_ targets: [Body]) -> V2? {
        var candidates: [(cost: Double, target: Body, pocket: V2, ghost: V2)] = []
        for target in targets {
            for pocket in pockets {
                let d = pocket - target.position
                let distance = d.length
                if distance < 1 { continue }
                let u = V2(d.x / distance, d.y / distance)
                let contact = target.radius + white.radius
                let ghost = target.position - u * contact
                if !(bounds.left + white.radius <= ghost.x && ghost.x <= bounds.right - white.radius
                     && bounds.top + white.radius <= ghost.y && ghost.y <= bounds.bottom - white.radius) {
                    continue
                }
                let w = ghost - white.position
                let approach = w.length
                let alignment = (w.x * u.x + w.y * u.y) / max(1, approach)
                if alignment > 0.53 {
                    candidates.append(((approach + distance) / alignment, target, pocket, ghost))
                }
            }
        }
        for candidate in candidates.sorted(by: { $0.cost < $1.cost }) {
            let others = targets.filter { $0 !== candidate.target }
            if Self.clear(white.position, candidate.ghost, others: others, radius: white.radius)
                && Self.clear(candidate.target.position, candidate.pocket, others: others,
                              radius: candidate.target.radius) {
                return candidate.ghost
            }
        }
        return nil
    }

    public func aimAt(_ point: V2) {
        guard state == .ready else { return }
        let d = point - white.position
        let length = d.length
        if length > 2 { aim = V2(d.x / length, d.y / length) }
    }

    @discardableResult
    public func shoot(power: Double) -> Bool {
        guard state == .ready else { return false }
        state = .stroke
        stroke = 0
        self.power = shotSpeed(power)
        breakShot = false
        return true
    }

    public func setCharge(_ value: Double) { charge = value }

    private func shotSpeed(_ power: Double) -> Double {
        bounds.height * (0.62 + 2.55 * max(0, min(1, power))) * 1.58
    }

    /// Cue stick endpoints (tip, tail), or nil when the cue is not shown.
    public func cue() -> (tip: V2, tail: V2)? {
        guard state == .ready || state == .stroke else { return nil }
        let pull = 12 + 34 * charge
        let gap = state == .stroke ? pull * max(0, 1 - stroke / 0.082) : pull
        let tip = white.position - aim * (white.radius + gap)
        var length = min(440, bounds.height * 0.48)
        for (value, direction, low, high) in [(tip.x, -aim.x, workArea.left + 5, workArea.right - 5),
                                              (tip.y, -aim.y, workArea.top + 5, workArea.bottom - 5)] {
            if abs(direction) > 1e-6 {
                let edge = direction > 0 ? high : low
                length = min(length, max(0, (edge - value) / direction))
            }
        }
        return (tip, tip - aim * length)
    }

    /// Predict the opening shot and one outgoing leg per moving ball.
    public func aimGuide() -> [GuideLine] {
        guard state == .ready else { return [] }
        let radius = white.radius
        let speed = shotSpeed(max(Self.minShotCharge, charge))
        let targets = activeIcons()
        let origin = white.position
        let velocity = aim * speed
        let leg = guideLeg(origin, velocity, radius: radius, obstacles: targets)
        var lines: [GuideLine] = []
        let gap = radius + 5
        if origin.distance(to: leg.end) > gap {
            lines.append(GuideLine(role: .incoming, start: origin + aim * gap, end: leg.end))
        }
        var outgoing: [(role: GuideRole, start: V2, motion: V2, size: Double, obstacles: [Body])] = []
        switch leg.contact {
        case .rail(let hitX, let hitY):
            let rebound = V2(hitX ? -leg.velocity.x * Self.railRebound : leg.velocity.x,
                             hitY ? -leg.velocity.y * Self.railRebound : leg.velocity.y)
            outgoing.append((.white, leg.end, rebound, radius, targets))
        case .ball(let target):
            let separation = leg.end.distance(to: target.position)
            if separation > 1e-6 {
                let n = V2((target.x - leg.end.x) / separation, (target.y - leg.end.y) / separation)
                let impulse = (leg.velocity.x * n.x + leg.velocity.y * n.y) * Self.ballImpulse
                let pushed = n * impulse
                let others = targets.filter { $0 !== target }
                outgoing.append((.white, leg.end, leg.velocity - pushed, radius, others))
                outgoing.append((.target, target.position, pushed, target.radius, others))
            }
        case .none:
            break
        }
        for out in outgoing {
            let end = guideLeg(out.start, out.motion, radius: out.size, obstacles: out.obstacles).end
            if out.start.distance(to: end) >= 2 {
                lines.append(GuideLine(role: out.role, start: out.start, end: end))
            }
        }
        return lines
    }

    private enum LegContact { case none, rail(Bool, Bool), ball(Body) }

    private func guideLeg(_ origin: V2, _ velocity: V2, radius: Double,
                          obstacles: [Body]) -> (end: V2, contact: LegContact, velocity: V2) {
        let speed = velocity.length
        let stop = bounds.height * Self.stopSpeed
        if speed <= stop { return (origin, .none, V2(0, 0)) }
        let d = V2(velocity.x / speed, velocity.y / speed)
        let drag = bounds.height * Self.rollingDrag
        var distance = (speed * speed - stop * stop) / (2 * drag)
        var contact = LegContact.none
        let railX = abs(d.x) > 1e-6
            ? ((d.x > 0 ? bounds.right - radius : bounds.left + radius) - origin.x) / d.x : .infinity
        let railY = abs(d.y) > 1e-6
            ? ((d.y > 0 ? bounds.bottom - radius : bounds.top + radius) - origin.y) / d.y : .infinity
        let rail = min(railX, railY)
        if rail <= distance {
            distance = max(0, rail)
            contact = .rail(abs(railX - rail) <= 1e-6, abs(railY - rail) <= 1e-6)
        }
        for body in obstacles {
            if let entry = rayCircle(origin, d, center: body.position, radius: radius + body.radius),
               entry < distance {
                distance = entry
                contact = .ball(body)
            }
        }
        for pocket in pockets {
            if let entry = rayCircle(origin, d, center: pocket, radius: pocketRadius + radius * 0.55),
               entry <= distance {
                distance = entry
                contact = .none
            }
        }
        let remaining = max(0, speed * speed - 2 * drag * distance).squareRoot()
        return (origin + d * distance, contact, d * remaining)
    }

    private func rayCircle(_ origin: V2, _ d: V2, center: V2, radius: Double) -> Double? {
        let offset = center - origin
        let forward = offset.x * d.x + offset.y * d.y
        let across = offset.x * d.y - offset.y * d.x
        let clearance = radius * radius - across * across
        if forward > 0 && clearance > 0 {
            return max(0, forward - clearance.squareRoot())
        }
        return nil
    }

    /// Advance the simulation with the runner's monotonic frame clock.
    public func step(_ rawDt: Double, now: Double) {
        var dt = max(0, min(0.05, rawDt))
        if !exits.isEmpty {
            exits = exits.compactMapValues { exit in
                let age = exit.age + dt
                return age < Self.exitSeconds ? (exit.x, exit.y, exit.tx, exit.ty, age) : nil
            }
        }
        if state == .finished { return }
        if roundStartedAt == nil { roundStartedAt = now }
        roundSeconds = Int(now - (roundStartedAt ?? now))
        if state == .returnWhite {
            readyFor += dt
            if readyFor >= 0.8 {
                state = .ballInHand
                autoPlace()
            }
            return
        }
        if state == .ballInHand { return }
        if state == .ready {
            readyFor += dt
            return
        }
        if state == .stroke {
            stroke += dt
            if stroke < 0.082 { return }
            white.vx = aim.x * power
            white.vy = aim.y * power
            state = .rolling
            dt = stroke - 0.082
        }
        let speed = activeBodies().map(\.speed).max() ?? 0
        let steps = max(1, Int((dt * max(180, speed / max(0.5, whiteRadius) * 1.7)).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            for (index, body) in bodies.enumerated() {
                if sunk.contains(index) { continue }
                body.x += body.vx * h
                body.y += body.vy * h
                if let pocket = inPocket(body) {
                    sunk.insert(index)
                    if index == 0 {
                        whiteSunk = true
                    } else {
                        startExit(index, body, pocket)
                    }
                } else {
                    walls(body)
                }
            }
            let active = activeBodies()
            collisions(active)
            for body in active {
                walls(body)
                let speed = body.speed
                if speed > 0 {
                    let drag = max(0, 1 - bounds.height * Self.rollingDrag * h / speed)
                    body.vx *= drag
                    body.vy *= drag
                }
                body.impact *= exp(-h * 12)
                body.angle *= exp(-h * 4)
            }
        }
        let cleared = pocketedIcons == icons.count
        let topSpeed = activeBodies().map(\.speed).max() ?? 0
        if cleared || topSpeed < bounds.height * Self.stopSpeed {
            for body in bodies {
                body.vx = 0; body.vy = 0; body.impact = 0; body.angle = 0
            }
            charge = 0
            readyFor = 0
            if cleared {
                state = .finished
            } else if whiteSunk {
                state = .returnWhite
            } else {
                state = .ready
                aim = defaultAim()
            }
        }
        poses = computePoses()
    }

    private func inPocket(_ body: Body) -> V2? {
        let capture = pocketRadius + body.radius * 0.55
        return pockets.first {
            let dx = body.x - $0.x, dy = body.y - $0.y
            return dx * dx + dy * dy < capture * capture
        }
    }

    private func startExit(_ index: Int, _ body: Body, _ pocket: V2) {
        let inset = min(48, max(5, (bounds.top - workArea.top) * 0.42))
        let tx = pocket.x == bounds.left ? workArea.left + inset
            : pocket.x == bounds.right ? workArea.right - inset : pocket.x
        let ty = pocket.y == bounds.top ? workArea.top + inset : workArea.bottom - inset
        exits[index] = (body.x, body.y, tx, ty, 0)
    }

    /// Position and fade of a sinking icon's exit animation.
    public func exitVisual(_ index: Int) -> (x: Double, y: Double, fade: Double)? {
        guard let exit = exits[index] else { return nil }
        let progress = exit.age / Self.exitSeconds
        let travel = 1 - pow(1 - min(1, progress / 0.73), 2)
        let fade = max(0, min(1, (progress - 0.40) / 0.60))
        return (exit.x + (exit.tx - exit.x) * travel, exit.y + (exit.ty - exit.y) * travel, fade)
    }

    @discardableResult
    public func placeWhite(_ point: V2) -> Bool {
        guard state == .ballInHand else { return false }
        let r = white.radius
        if !(bounds.left + r <= point.x && point.x <= bounds.right - r
             && bounds.top + r <= point.y && point.y <= bounds.bottom - r) { return false }
        if pockets.contains(where: { $0.distance(to: point) < pocketRadius + r }) { return false }
        if activeBodies().contains(where: { $0.position.distance(to: point) < r + $0.radius + 2 }) {
            return false
        }
        white.x = point.x
        white.y = point.y
        sunk.remove(0)
        whiteSunk = false
        state = .ready
        readyFor = 0
        aim = defaultAim()
        return true
    }

    private func autoPlace() {
        for fx in [0.20, 0.31, 0.42, 0.54, 0.66, 0.78] {
            for fy in [0.5, 0.31, 0.69, 0.19, 0.81] {
                if placeWhite(V2(bounds.left + bounds.width * fx, bounds.top + bounds.height * fy)) {
                    return
                }
            }
        }
    }

    private func walls(_ body: Body) {
        let lowX = bounds.left + body.radius, highX = bounds.right - body.radius
        let lowY = bounds.top + body.radius, highY = bounds.bottom - body.radius
        if body.x < lowX || body.x > highX {
            let position = body.x, speed = body.vx
            body.x = max(lowX, min(highX, position))
            if (position < lowX && speed < 0) || (position > highX && speed > 0) {
                body.vx = -speed * Self.railRebound
                body.impact = max(body.impact, min(0.23, abs(speed) / bounds.height * 0.25))
            }
        }
        if body.y < lowY || body.y > highY {
            let position = body.y, speed = body.vy
            body.y = max(lowY, min(highY, position))
            if (position < lowY && speed < 0) || (position > highY && speed > 0) {
                body.vy = -speed * Self.railRebound
                body.impact = max(body.impact, min(0.23, abs(speed) / bounds.height * 0.25))
            }
        }
    }

    private func collisions(_ bodies: [Body]) {
        let cell = max(1, radius * 2)
        var buckets: [SIMD2<Int>: [Body]] = [:]
        for body in bodies {
            let gx = Int((body.x / cell).rounded(.down))
            let gy = Int((body.y / cell).rounded(.down))
            for y in (gy - 1)...(gy + 1) {
                for x in (gx - 1)...(gx + 1) {
                    for other in buckets[SIMD2(x, y)] ?? [] {
                        collide(other, body)
                    }
                }
            }
            buckets[SIMD2(gx, gy), default: []].append(body)
        }
    }

    private func collide(_ a: Body, _ b: Body) {
        let dx = b.x - a.x, dy = b.y - a.y
        let limit = a.radius + b.radius
        if dx * dx + dy * dy >= limit * limit { return }
        let distance = (dx * dx + dy * dy).squareRoot()
        let n = distance > 1e-6 ? V2(dx / distance, dy / distance) : V2(1, 0)
        let correction = (limit - distance) * 0.5
        a.x -= n.x * correction; a.y -= n.y * correction
        b.x += n.x * correction; b.y += n.y * correction
        let closing = (b.vx - a.vx) * n.x + (b.vy - a.vy) * n.y
        if closing >= 0 { return }
        let impulse = -closing * Self.ballImpulse
        a.vx -= n.x * impulse; a.vy -= n.y * impulse
        b.vx += n.x * impulse; b.vy += n.y * impulse
        let impact = min(0.23, impulse / bounds.height * 0.30)
        a.impact = max(a.impact, impact)
        b.impact = max(b.impact, impact)
        a.angle -= n.y * impact * 95
        b.angle += n.y * impact * 95
    }

    private func computePoses() -> [Pose] {
        zip(icons, sizes).map { body, size in
            let ratio = tile / max(size.x, size.y)
            return Pose(x: body.x, y: body.y,
                        width: max(1, (size.x * ratio * (1 + body.impact * 0.64)).rounded()),
                        height: max(1, (size.y * ratio * (1 - body.impact)).rounded()),
                        angle: body.angle)
        }
    }
}