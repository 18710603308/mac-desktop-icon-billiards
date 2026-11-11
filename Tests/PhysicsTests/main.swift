import BilliardsCore
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("ok   \(message)")
    } else {
        failures += 1
        print("FAIL \(message)")
    }
}

let work = TableRect(0, 0, 1600, 900)

func makeTable(_ count: Int) -> BilliardsMotion {
    BilliardsMotion(workArea: work, sizes: Array(repeating: V2(64, 64), count: count))
}

func run(_ table: BilliardsMotion, seconds: Double, now: inout Double) {
    let frames = Int(seconds * 60)
    for _ in 0..<frames {
        now += 1.0 / 60
        table.step(1.0 / 60, now: now)
    }
}

// Rack geometry: every icon lands inside the cushions, in a triangle.
do {
    let table = makeTable(15)
    check(table.icons.count == 15, "rack holds one body per icon")
    check(table.rack.count == 15, "rack positions match icon count")
    let inside = table.icons.allSatisfy {
        $0.x > table.bounds.left && $0.x < table.bounds.right
            && $0.y > table.bounds.top && $0.y < table.bounds.bottom
    }
    check(inside, "rack sits inside the cushions")
    check(table.pockets.count == 6, "six pockets")
    check(table.white.x < table.icons.map(\.x).min()!, "cue ball starts left of the rack")
}

// A full-power break settles back to a resting state with no residual motion.
do {
    let table = makeTable(15)
    var now = 0.0
    check(table.shoot(power: 1), "break shot accepted from ready")
    run(table, seconds: 25, now: &now)
    check(table.state == .ready || table.state == .finished, "break settles (state \(table.state))")
    check(table.activeBodies().allSatisfy { $0.speed == 0 }, "all bodies at rest after the break")
    check(table.roundSeconds >= 20, "round clock advances")
}

// Cushion rebound keeps the rebound coefficient and flips the velocity.
do {
    let table = makeTable(1)
    var now = 0.0
    table.shoot(power: 0.3)
    run(table, seconds: 0.12, now: &now)
    check(table.state == .rolling, "shot reaches rolling state")
    table.white.x = table.bounds.left + table.whiteRadius + 1
    table.white.y = (table.bounds.top + table.bounds.bottom) / 2
    table.white.vx = -600
    table.white.vy = 0
    table.step(1.0 / 60, now: now)
    check(table.white.vx > 0, "left cushion reverses horizontal velocity")
    check(abs(table.white.vx - 600 * BilliardsMotion.railRebound) < 40,
          "rebound keeps the rail coefficient (vx \(table.white.vx))")
}

// Head-on collision transfers momentum along the contact normal.
do {
    let table = makeTable(1)
    var now = 0.0
    table.shoot(power: 0.3)
    run(table, seconds: 0.12, now: &now)
    let a = table.white
    let b = table.icons[0]
    a.x = table.bounds.left + 200
    a.y = (table.bounds.top + table.bounds.bottom) / 2
    b.x = a.x + a.radius + b.radius - 2
    b.y = a.y
    b.vx = 0; b.vy = 0
    a.vx = 500; a.vy = 0
    table.step(1.0 / 60, now: now)
    check(b.vx > 0, "struck body gains forward velocity")
    check(a.vx < 500, "striking body loses velocity")
}

// A scratch returns the cue ball through ball-in-hand and auto placement.
do {
    let table = makeTable(2)
    var now = 0.0
    var sawScratch = false
    table.aimAt(table.pockets[0])
    check(table.shoot(power: 0.8), "scratch shot accepted")
    for _ in 0..<360 {
        now += 1.0 / 60
        table.step(1.0 / 60, now: now)
        if table.sunk.contains(0) { sawScratch = true }
    }
    check(sawScratch, "cue ball pocketed on a scratch")
    check(table.state == .ready, "auto placement restores ready (state \(table.state))")
    check(!table.sunk.contains(0), "cue ball back in play")
    let r = table.whiteRadius
    check(table.white.x >= table.bounds.left + r && table.white.x <= table.bounds.right - r,
          "placed cue ball inside cushions")
    check(table.white.position.distance(to: table.pockets[0]) > table.pocketRadius + r,
          "auto placement moves the cue ball away from the pocket")
}

// Ball-in-hand rejects illegal placements and accepts a legal one.
// Cover every auto-placement candidate so the scratch leaves ball-in-hand open.
do {
    let scratch = makeTable(30)
    var candidate = 0
    for fx in [0.20, 0.31, 0.42, 0.54, 0.66, 0.78] {
        for fy in [0.5, 0.31, 0.69, 0.19, 0.81] {
            scratch.icons[candidate].x = scratch.bounds.left + scratch.bounds.width * fx
            scratch.icons[candidate].y = scratch.bounds.top + scratch.bounds.height * fy
            candidate += 1
        }
    }
    scratch.white.x = scratch.bounds.left + scratch.bounds.width * 0.06
    scratch.white.y = (scratch.bounds.top + scratch.bounds.bottom) / 2
    scratch.aimAt(scratch.pockets[0])
    scratch.shoot(power: 0.8)
    var t = 0.0
    for _ in 0..<600 {
        t += 1.0 / 60
        scratch.step(1.0 / 60, now: t)
        if scratch.state == .ballInHand { break }
    }
    check(scratch.state == .ballInHand, "scratch reaches ball-in-hand when auto placement fails")
    check(!scratch.placeWhite(V2(scratch.bounds.left - 50, scratch.bounds.top + 100)),
          "placement outside cushions rejected")
    check(!scratch.placeWhite(scratch.pockets[3]), "placement on a pocket rejected")
    check(!scratch.placeWhite(scratch.icons[0].position), "placement on an icon rejected")
    check(scratch.placeWhite(V2(scratch.bounds.left + scratch.bounds.width * 0.10,
                                scratch.bounds.top + scratch.bounds.height * 0.5)),
          "legal placement accepted")
    check(scratch.state == .ready, "placement returns to ready")
}

// Potting the only icon finishes the round (straight line into the top pocket).
do {
    let table = makeTable(1)
    table.icons[0].x = 800
    table.icons[0].y = 300
    table.white.x = 800
    table.white.y = 600
    var now = 0.0
    table.aimAt(table.icons[0].position)
    table.shoot(power: 0.7)
    run(table, seconds: 20, now: &now)
    check(table.pocketedIcons == 1, "icon counted as pocketed")
    check(table.state == .finished, "clearing the table finishes the round")
}

// The break trajectory matches the Windows edition's Python engine frame for frame.
do {
    let expected: [Int: [[Double]]] = [
        30: [[717.085588, 629.747658], [819.301784, 523.23048], [909.825509, 343.269894],
             [913.370486, 516.99468], [999.09941, 341.544609], [977.362519, 452.950908],
             [992.823221, 563.15412], [1062.294021, 282.508759], [1063.046855, 413.29056],
             [1072.753695, 499.60221], [1085.832512, 623.862009], [1190.678975, 284.334502],
             [1145.645457, 362.671646], [1147.059582, 452.822848], [1166.163503, 572.89803],
             [1444.254266, 757.141781]],
        60: [[653.288753, 753.537814], [603.362637, 596.409155], [856.752138, 303.256508],
             [818.061901, 619.325369], [991.498835, 302.503604], [920.988033, 409.25343],
             [972.910414, 574.142098], [780.064524, 252.007005], [1055.456391, 398.19952],
             [1089.398127, 574.899802], [920.59312, 746.736634], [955.082288, 136.152369],
             [1154.577733, 369.393132], [1124.505074, 479.873496], [1219.512439, 547.469691],
             [1390.870752, 451.116632]],
        120: [[605.035003, 613.453076], [376.491848, 702.608647], [853.156063, 300.682552],
              [538.228225, 384.237369], [957.040702, 224.345356], [916.757411, 405.974153],
              [972.910414, 574.142098], [410.849054, 582.849063], [1015.351424, 382.762291],
              [1091.967864, 582.636755], [908.404203, 633.283372], [792.314629, 138.32422],
              [1154.577733, 369.393132], [1122.971369, 479.634898], [1397.29122, 383.351191],
              [1456.99137, 235.977874]],
    ]
    let table = makeTable(15)
    table.shoot(power: 1)
    var now = 0.0
    var maxError = 0.0
    for frame in 1...120 {
        now += 1.0 / 60
        table.step(1.0 / 60, now: now)
        if let want = expected[frame] {
            for (body, pair) in zip(table.bodies, want) {
                maxError = max(maxError, abs(body.x - pair[0]), abs(body.y - pair[1]))
            }
        }
    }
    check(maxError < 1e-4, "break trajectory matches the Windows reference (max error \(maxError))")
}

// The aim guide predicts an incoming leg plus outgoing legs on contact.
do {
    let table = makeTable(1)
    table.aimAt(table.icons[0].position)
    let lines = table.aimGuide()
    check(lines.contains { $0.role == .incoming }, "guide shows the incoming path")
    check(lines.contains { $0.role == .target }, "guide shows the struck icon's path")
    check(table.aimGuide().allSatisfy { $0.start.distance(to: $0.end) >= 2 },
          "guide legs have visible length")
}

// Charge is clamped and the shot speed grows with it.
do {
    let table = makeTable(0)
    table.aimAt(V2(table.white.x + 100, table.white.y))
    table.shoot(power: 0)
    let slow = table.power
    table.reset()
    table.aimAt(V2(table.white.x + 100, table.white.y))
    table.shoot(power: 1)
    check(table.power > slow, "full charge is faster than minimum charge")
    check(table.state == .stroke, "shot enters the stroke animation")
}

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)