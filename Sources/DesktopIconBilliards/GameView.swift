import AppKit
import BilliardsCore

/// The whole game drawn on one flipped (top-left origin) desktop-level view.
final class GameView: NSView {
    private let items: [DesktopItem]
    let table: BilliardsMotion
    private let background: NSImage
    private let whiteImage: NSImage
    private let introOrigins: [V2]
    private var introElapsed: Double? = 0
    private var guideEnabled = true
    private var heldSince: Double?
    private var chargeOrigin: V2?
    private var lastNow = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    var buttons: [(rect: CGRect, action: () -> Void)] = []
    var onQuit: () -> Void = {}

    private static let introDuration = 1.25
    private static let introStagger = 0.025

    init(items: [DesktopItem], table: BilliardsMotion, screen: NSScreen) {
        self.items = items
        self.table = table
        let wallpaper = NSWorkspace.shared.desktopImageURL(for: screen)
            .flatMap { NSImage(contentsOf: $0) }
        background = Artwork.tableBackground(size: screen.frame.size,
                                             scale: screen.backingScaleFactor,
                                             table: table, wallpaper: wallpaper)
        whiteImage = Artwork.cueBall(radius: table.whiteRadius)
        let count = max(1, items.count)
        let columns = max(1, Int((Double(count) * 1.7).squareRoot().rounded(.up)))
        let rows = max(1, Int((Double(count) / Double(columns)).rounded(.up)))
        introOrigins = (0..<items.count).map { index in
            let column = index % columns, row = index / columns
            let fx = columns == 1 ? 0.5 : Double(column) / Double(columns - 1)
            let fy = rows == 1 ? 0.5 : Double(row) / Double(rows - 1)
            return V2(table.bounds.left + table.bounds.width * (0.10 + 0.80 * fx),
                      table.bounds.top + table.bounds.height * (0.12 + 0.76 * fy))
        }
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func start() {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastNow
        lastNow = now
        if let elapsed = introElapsed {
            let next = elapsed + max(0, min(0.05, dt))
            introElapsed = next >= Self.introDuration + 6 * Self.introStagger ? nil : next
        } else {
            if let held = heldSince {
                table.setCharge(min(1, (now - held) / 0.9))
            }
            table.step(dt, now: now)
        }
        needsDisplay = true
    }

    // MARK: drawing

    override func draw(_ dirtyRect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        background.draw(in: bounds)
        buttons = []
        drawIcons(ctx)
        drawWhite()
        if introElapsed == nil {
            drawCue(ctx)
            if guideEnabled { drawGuide(ctx) }
            drawCharge()
        }
        drawHUD()
        if table.state == .ballInHand { drawHint() }
        if table.state == .finished { drawSummary() }
    }

    private func drawIcons(_ ctx: CGContext) {
        for (index, pose) in table.poses.enumerated() {
            var x = pose.x, y = pose.y, width = pose.width, height = pose.height
            var fraction = 1.0, fade = 0.0
            if let elapsed = introElapsed {
                let t = max(0, min(1, (elapsed - Double(index % 7) * Self.introStagger) / Self.introDuration))
                let ease = t * t * t * (t * (t * 6 - 15) + 10)
                let origin = introOrigins[index]
                let dx = pose.x - origin.x, dy = pose.y - origin.y
                let distance = max(1, (dx * dx + dy * dy).squareRoot())
                let arc = pow(sin(Double.pi * t), 2) * min(65, distance * 0.10) * (index % 2 == 0 ? 1 : -1)
                x = origin.x + dx * ease - dy / distance * arc
                y = origin.y + dy * ease + dx / distance * arc
            } else if table.sunk.contains(index + 1) {
                guard let exit = table.exitVisual(index + 1) else { continue }
                x = exit.x; y = exit.y; fade = exit.fade
                width = max(1, width * (1 - fade * 0.54))
                height = max(1, height * (1 - fade * 0.54))
                fraction = pow(1 - fade, 1.35)
            }
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: -pose.angle * Double.pi / 180)
            items[index].image.draw(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                    from: .zero, operation: .sourceOver, fraction: fraction)
            ctx.restoreGState()
            if fade > 0 { drawParticles(ctx, index: index, fade: fade, at: V2(x, y)) }
        }
    }

    private func drawParticles(_ ctx: CGContext, index: Int, fade: Double, at center: V2) {
        for i in 0..<9 {
            let angle = Double(i) * 2 * Double.pi / 9 + Double(index) * 0.61
            let distance = fade * (20 + Double(i % 3) * 8)
            let size = max(0.7, (1 - fade) * (2.5 + Double(i % 3)))
            let alpha = (230 * pow(sin(Double.pi * fade), 0.65)).rounded() / 255
            let rect = CGRect(x: center.x + cos(angle) * distance - size,
                              y: center.y + sin(angle) * distance - size,
                              width: size * 2, height: size * 2)
            ctx.setFillColor(Artwork.color(173, 255, 221, Int(alpha * 255)).cgColor)
            ctx.fillEllipse(in: rect)
        }
    }

    private func drawWhite() {
        guard !table.whiteSunk else { return }
        let size = whiteImage.size
        whiteImage.draw(in: CGRect(x: table.white.x - size.width / 2, y: table.white.y - size.height / 2,
                                   width: size.width, height: size.height))
    }

    private func drawCue(_ ctx: CGContext) {
        guard let cue = table.cue() else { return }
        let thickness = 1.65
        ctx.setLineCap(.round)
        func stroke(_ from: V2, _ to: V2, _ width: Double, _ color: NSColor) {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: from.x, y: from.y))
            ctx.addLine(to: CGPoint(x: to.x, y: to.y))
            ctx.strokePath()
        }
        stroke(cue.tail, cue.tip, 7 * thickness, Artwork.color(60, 37, 22, 220))
        stroke(cue.tail, cue.tip, 4 * thickness, Artwork.color(239, 193, 126))
        let grip = cue.tail + (cue.tip - cue.tail) * 0.37
        stroke(cue.tail, grip, 5 * thickness, Artwork.color(127, 79, 48))
        ctx.setFillColor(Artwork.color(126, 207, 228).cgColor)
        let r = 2 * thickness
        ctx.fillEllipse(in: CGRect(x: cue.tip.x - r, y: cue.tip.y - r, width: r * 2, height: r * 2))
    }

    private func drawGuide(_ ctx: CGContext) {
        let colors: [GuideRole: NSColor] = [
            .incoming: Artwork.color(235, 250, 245, 196),
            .white: Artwork.color(167, 216, 255, 208),
            .target: Artwork.color(112, 239, 181, 224),
        ]
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [8, 8])
        for line in table.aimGuide() {
            let color = colors[line.role] ?? .white
            ctx.setStrokeColor(color.cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: line.start.x, y: line.start.y))
            ctx.addLine(to: CGPoint(x: line.end.x, y: line.end.y))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokeEllipse(in: CGRect(x: line.end.x - 4, y: line.end.y - 4, width: 8, height: 8))
            ctx.setLineDash(phase: 0, lengths: [8, 8])
        }
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawCharge() {
        guard let origin = chargeOrigin, table.state == .ready else { return }
        let fontSize = 14.0
        let pad = max(4, fontSize / 2)
        let width = fontSize * 8, height = fontSize * 2 + pad
        let bounds = table.bounds
        var x = origin.x + fontSize
        if x + width > bounds.right { x = origin.x - fontSize - width }
        var y = origin.y + fontSize
        if y + height > bounds.bottom { y = origin.y - fontSize - height }
        x = max(bounds.left, x); y = max(bounds.top, y)
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let path = NSBezierPath(roundedRect: frame, xRadius: pad, yRadius: pad)
        Artwork.color(13, 25, 23, 248).setFill(); path.fill()
        Artwork.color(105, 221, 179, 240).setStroke(); path.lineWidth = 1; path.stroke()
        text("力度", CGPoint(x: x + pad, y: y + height / 2 - fontSize / 2),
             font: .systemFont(ofSize: fontSize), color: Artwork.color(235, 250, 243))
        let left = x + pad * 2 + fontSize * 2
        let top = y + (height - pad) / 2
        let barWidth = width - pad - (left - x)
        let bar = NSBezierPath(roundedRect: CGRect(x: left, y: top, width: barWidth, height: pad),
                               xRadius: pad / 2, yRadius: pad / 2)
        Artwork.color(49, 76, 70).setFill(); bar.fill()
        let fillWidth = (barWidth * table.charge).rounded()
        if fillWidth > 0 {
            let fill = NSBezierPath(roundedRect: CGRect(x: left, y: top, width: fillWidth, height: pad),
                                    xRadius: min(pad, fillWidth) / 2, yRadius: min(pad, fillWidth) / 2)
            Artwork.color(111, 239, 185).setFill(); fill.fill()
        }
    }

    private func drawHUD() {
        let bounds = table.bounds
        let frame = CGRect(x: bounds.left + 18, y: bounds.top + 18, width: 372, height: 104)
        let path = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
        Artwork.color(13, 25, 23, 235).setFill(); path.fill()
        Artwork.color(105, 221, 179, 120).setStroke(); path.lineWidth = 1; path.stroke()
        text("桌面图标台球", CGPoint(x: frame.minX + 14, y: frame.minY + 12),
             font: .systemFont(ofSize: 13, weight: .semibold), color: Artwork.color(235, 250, 243))
        let stats = String(format: "用时 %@   进球 %d   剩余 %d", Self.clock(table.roundSeconds),
                           table.pocketedIcons, table.icons.count - table.pocketedIcons)
        text(stats, CGPoint(x: frame.minX + 14, y: frame.minY + 38),
             font: .systemFont(ofSize: 12), color: Artwork.color(178, 214, 200))
        var x = frame.minX + 14
        let y = frame.minY + 64
        for (title, width, action) in [
            ("辅助线 · \(guideEnabled ? "开" : "关")", 96.0, { [weak self] in self?.guideEnabled.toggle() }),
            ("重新开始", 84.0, { [weak self] in self?.restart() }),
            ("退出", 60.0, { [weak self] in self?.onQuit() }),
        ] as [(String, Double, () -> Void)] {
            let rect = CGRect(x: x, y: y, width: width, height: 26)
            button(title, rect: rect)
            buttons.append((rect, action))
            x += width + 8
        }
    }

    private func drawHint() {
        let message = "白球入袋 · 点击台面空处放置白球"
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let size = (message as NSString).size(withAttributes: [.font: font])
        let bounds = table.bounds
        let frame = CGRect(x: bounds.left + bounds.width / 2 - size.width / 2 - 14,
                           y: bounds.top + 20, width: size.width + 28, height: 30)
        let path = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)
        Artwork.color(13, 25, 23, 235).setFill(); path.fill()
        text(message, CGPoint(x: frame.midX, y: frame.midY - 8), font: font,
             color: Artwork.color(235, 250, 243), align: .center)
    }

    private func drawSummary() {
        let bounds = table.bounds
        let frame = CGRect(x: bounds.left + bounds.width / 2 - 180,
                           y: bounds.top + bounds.height / 2 - 100, width: 360, height: 200)
        let path = NSBezierPath(roundedRect: frame, xRadius: 16, yRadius: 16)
        Artwork.color(13, 25, 23, 246).setFill(); path.fill()
        Artwork.color(105, 221, 179, 200).setStroke(); path.lineWidth = 1.5; path.stroke()
        text("清台!", CGPoint(x: frame.midX, y: frame.minY + 26),
             font: .systemFont(ofSize: 22, weight: .bold), color: Artwork.color(111, 239, 185),
             align: .center)
        text("总用时 \(Self.clock(table.roundSeconds))", CGPoint(x: frame.midX, y: frame.minY + 70),
             font: .systemFont(ofSize: 15), color: Artwork.color(235, 250, 243), align: .center)
        text("图标总数 \(table.icons.count)", CGPoint(x: frame.midX, y: frame.minY + 98),
             font: .systemFont(ofSize: 15), color: Artwork.color(235, 250, 243), align: .center)
        let restartRect = CGRect(x: frame.midX - 108, y: frame.minY + 140, width: 100, height: 30)
        let quitRect = CGRect(x: frame.midX + 8, y: frame.minY + 140, width: 100, height: 30)
        button("重新开始", rect: restartRect, primary: true)
        button("退出", rect: quitRect)
        buttons.append((restartRect, { [weak self] in self?.restart() }))
        buttons.append((quitRect, { [weak self] in self?.onQuit() }))
    }

    private func button(_ title: String, rect: CGRect, primary: Bool = false) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        (primary ? Artwork.color(111, 239, 185) : Artwork.color(49, 76, 70)).setFill()
        path.fill()
        text(title, CGPoint(x: rect.midX, y: rect.midY - 7),
             font: .systemFont(ofSize: 12, weight: .medium),
             color: primary ? Artwork.color(10, 25, 20) : Artwork.color(235, 250, 243), align: .center)
    }

    private func text(_ string: String, _ point: CGPoint, font: NSFont, color: NSColor,
                      align: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        let attributes: [NSAttributedString.Key: Any] =
            [.font: font, .foregroundColor: color, .paragraphStyle: style]
        var origin = point
        if align == .center {
            origin.x -= (string as NSString).size(withAttributes: attributes).width / 2
        }
        (string as NSString).draw(at: origin, withAttributes: attributes)
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    private func point(_ event: NSEvent) -> V2 {
        let p = convert(event.locationInWindow, from: nil)
        return V2(Double(p.x), Double(p.y))
    }

    private func aim(_ event: NSEvent) {
        guard introElapsed == nil else { return }
        table.aimAt(point(event))
    }

    override func mouseMoved(with event: NSEvent) { aim(event) }
    override func mouseDragged(with event: NSEvent) { aim(event) }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        let cg = CGPoint(x: p.x, y: p.y)
        if let hit = buttons.first(where: { $0.rect.contains(cg) }) {
            hit.action()
            return
        }
        guard introElapsed == nil else { return }
        if table.state == .ballInHand {
            table.placeWhite(p)
            return
        }
        if table.state == .ready {
            heldSince = ProcessInfo.processInfo.systemUptime
            chargeOrigin = p
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard heldSince != nil else { return }
        let power = max(BilliardsMotion.minShotCharge, table.charge)
        heldSince = nil
        chargeOrigin = nil
        let p = point(event)
        let bounds = table.bounds
        if bounds.left <= p.x && p.x <= bounds.right && bounds.top <= p.y && p.y <= bounds.bottom {
            table.shoot(power: power)
        } else {
            table.setCharge(0)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "r": restart()
        case "g": guideEnabled.toggle()
        default:
            if event.keyCode == 53 { onQuit() } else { super.keyDown(with: event) }
        }
    }

    func restart() {
        table.reset()
        heldSince = nil
        chargeOrigin = nil
        needsDisplay = true
    }
}