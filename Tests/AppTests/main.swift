@testable import BilliardsApp
import BilliardsCore
import AppKit

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("ok   \(message)")
    } else {
        failures += 1
        print("FAIL \(message)")
    }
}

guard let screen = NSScreen.main else {
    print("FAIL no screen available")
    exit(1)
}
let frame = screen.frame
let work = TableRect(0, 0, Double(frame.width), Double(frame.height))
let items = DesktopItems.load(demo: true)
let table = BilliardsMotion(workArea: work, sizes: items.map(\.size))
let view = GameView(items: items, table: table, screen: screen)

// Let the rack fly-in finish; input is ignored during the intro.
view.start()
RunLoop.main.run(until: Date().addingTimeInterval(1.6))
view.stop()

func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: frame.height - y), modifierFlags: [],
                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}

func key(_ character: String, _ code: UInt16) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                     context: nil, characters: character, charactersIgnoringModifiers: character,
                     isARepeat: false, keyCode: code)!
}

func settle(_ seconds: Double) {
    var now = ProcessInfo.processInfo.systemUptime
    for _ in 0..<Int(seconds * 60) {
        now += 1.0 / 60
        table.step(1.0 / 60, now: now)
    }
}

// Moving the mouse aims the cue ball.
do {
    let target = CGPoint(x: table.white.x + 300, y: table.white.y)
    view.mouseMoved(with: mouse(.mouseMoved, target.x, target.y))
    check(abs(table.aim.x - 1) < 1e-6 && abs(table.aim.y) < 1e-6, "mouse move aims horizontally")
}

// Press and release inside the table fires a shot.
do {
    let p = CGPoint(x: table.white.x + 300, y: table.white.y)
    view.mouseDown(with: mouse(.leftMouseDown, p.x, p.y))
    view.mouseUp(with: mouse(.leftMouseUp, p.x, p.y))
    check(table.state == .stroke, "press+release fires a shot")
    settle(0.2)
    check(table.state == .rolling, "shot enters rolling")
    settle(20)
    check(table.state == .ready || table.state == .finished, "shot settles")
}

// Releasing outside the cushions cancels the charge instead of shooting.
do {
    table.reset()
    let inside = CGPoint(x: table.white.x + 200, y: table.white.y)
    view.mouseDown(with: mouse(.leftMouseDown, inside.x, inside.y))
    view.mouseUp(with: mouse(.leftMouseUp, 5, 5))
    check(table.state == .ready, "release outside the table cancels the shot")
}

// Holding longer charges a stronger shot.
do {
    table.reset()
    let p = CGPoint(x: table.white.x + 200, y: table.white.y)
    view.mouseDown(with: mouse(.leftMouseDown, p.x, p.y))
    view.start()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    view.mouseUp(with: mouse(.leftMouseUp, p.x, p.y))
    view.stop()
    let weak = table.power
    table.reset()
    view.mouseDown(with: mouse(.leftMouseDown, p.x, p.y))
    view.start()
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    view.mouseUp(with: mouse(.leftMouseUp, p.x, p.y))
    view.stop()
    check(table.power > weak, "longer hold charges more power (\(weak) -> \(table.power))")
}

// The HUD restart button resets the round.
do {
    settle(0.2)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(frame.width),
                               pixelsHigh: Int(frame.height), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    let bounds = table.bounds
    let restart = CGPoint(x: bounds.left + 18 + 14 + 96 + 8 + 40, y: bounds.top + 18 + 64 + 13)
    view.mouseDown(with: mouse(.leftMouseDown, restart.x, restart.y))
    check(table.state == .ready && table.roundSeconds == 0, "HUD restart button resets the round")
}

// R restarts and Esc quits.
do {
    view.mouseDown(with: mouse(.leftMouseDown, table.white.x + 200, table.white.y))
    view.mouseUp(with: mouse(.leftMouseUp, table.white.x + 200, table.white.y))
    view.keyDown(with: key("r", 15))
    check(table.state == .ready, "R key restarts")
    var quit = false
    view.onQuit = { quit = true }
    view.keyDown(with: key("", 53))
    check(quit, "Esc triggers quit")
}

print(failures == 0 ? "\nALL APP TESTS PASSED" : "\n\(failures) APP TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)