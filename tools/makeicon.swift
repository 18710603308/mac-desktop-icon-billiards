import AppKit

// Draws a 1024x1024 master app icon: green felt tile, six pockets, a white cue
// ball and a racked app-icon ball, matching the in-game look.
let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: CGFloat(a)/255)
}

// Rounded-square felt background.
let tile = CGRect(x: 40, y: 40, width: size-80, height: size-80)
let bg = NSBezierPath(roundedRect: tile, xRadius: 200, yRadius: 200)
color(16, 62, 52).setFill(); bg.fill()
let felt = NSBezierPath(roundedRect: tile.insetBy(dx: 26, dy: 26), xRadius: 176, yRadius: 176)
color(23, 84, 70).setFill(); felt.fill()

// Rails.
color(105, 221, 179, 160).setStroke()
let rail = NSBezierPath(roundedRect: tile.insetBy(dx: 60, dy: 60), xRadius: 150, yRadius: 150)
rail.lineWidth = 10; rail.stroke()

// Pockets (corners + top/bottom mid).
let pr = 62.0
let pockets: [CGPoint] = [
    CGPoint(x: 120, y: 120), CGPoint(x: size/2, y: 96), CGPoint(x: size-120, y: 120),
    CGPoint(x: 120, y: size-120), CGPoint(x: size/2, y: size-96), CGPoint(x: size-120, y: size-120),
]
for p in pockets {
    color(8, 14, 13).setFill()
    NSBezierPath(ovalIn: CGRect(x: p.x-pr, y: p.y-pr, width: pr*2, height: pr*2)).fill()
    color(105, 221, 179, 120).setStroke()
    let ring = NSBezierPath(ovalIn: CGRect(x: p.x-pr, y: p.y-pr, width: pr*2, height: pr*2))
    ring.lineWidth = 8; ring.stroke()
}

// Racked icon-ball (a rounded app tile) on the right.
let ballRect = CGRect(x: 560, y: 400, width: 250, height: 250)
let ball = NSBezierPath(roundedRect: ballRect, xRadius: 60, yRadius: 60)
color(235, 240, 245).setFill(); ball.fill()
color(255, 122, 60).setFill()
NSBezierPath(roundedRect: ballRect.insetBy(dx: 52, dy: 52), xRadius: 34, yRadius: 34).fill()

// Cue ball with a soft highlight on the left.
let cr = 110.0
let c = CGPoint(x: 330, y: 512)
let grad = NSGradient(colors: [color(255,255,255), color(210,222,228), color(160,175,182)])!
grad.draw(in: NSBezierPath(ovalIn: CGRect(x: c.x-cr, y: c.y-cr, width: cr*2, height: cr*2)),
          relativeCenterPosition: NSPoint(x: -0.35, y: 0.35))

// Cue stick aiming at the cue ball.
ctx.setLineCap(.round)
color(239, 193, 126).setStroke()
let stick = NSBezierPath()
stick.move(to: CGPoint(x: 120, y: 300))
stick.line(to: CGPoint(x: 250, y: 452))
stick.lineWidth = 26; stick.stroke()

NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("icon written")