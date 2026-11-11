import AppKit
import BilliardsCore
import CoreImage

enum Artwork {
    static func color(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255,
                alpha: CGFloat(a) / 255)
    }

    /// Wallpaper, dimmed surround, blurred felt and the six pockets, baked once.
    static func tableBackground(size: CGSize, scale: CGFloat, table: BilliardsMotion,
                                wallpaper: NSImage?) -> NSImage {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        let h = size.height
        func rect(_ x: Double, _ y: Double, _ w: Double, _ hh: Double) -> CGRect {
            CGRect(x: x, y: h - y - hh, width: w, height: hh)
        }
        func point(_ v: V2) -> CGPoint { CGPoint(x: v.x, y: h - v.y) }

        let wallCG = wallpaper?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if let wallCG {
            context.draw(wallCG, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        } else {
            context.setFillColor(color(10, 20, 22).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        let work = table.workArea
        context.setFillColor(color(8, 26, 25, 40).cgColor)
        context.fill(rect(work.left, work.top, work.width, work.height))

        let bounds = table.bounds
        let feltRect = rect(bounds.left, bounds.top, bounds.width, bounds.height)
        if let wallCG, let blurred = blur(wallCG, radius: max(10, bounds.height / 55) * Double(scale)) {
            let crop = CGRect(x: bounds.left * scale, y: (h - bounds.bottom) * scale,
                              width: bounds.width * scale, height: bounds.height * scale)
            if let piece = blurred.cropping(to: crop) {
                context.draw(piece, in: feltRect)
            }
        } else {
            context.setFillColor(color(14, 82, 63, 156).cgColor)
            context.fill(feltRect)
        }
        context.setStrokeColor(color(105, 221, 179, 184).cgColor)
        context.setLineWidth(3)
        context.stroke(feltRect.insetBy(dx: 1.5, dy: 1.5))

        let r = table.pocketRadius.rounded()
        for pocket in table.pockets {
            let center = point(pocket)
            let outer = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.setFillColor(color(11, 22, 21, 215).cgColor)
            context.fillEllipse(in: outer)
            context.setStrokeColor(color(105, 221, 179, 135).cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: outer.insetBy(dx: 1, dy: 1))
            let inset = r * 0.23
            context.setFillColor(color(4, 10, 11).cgColor)
            context.fillEllipse(in: outer.insetBy(dx: inset, dy: inset))
        }
        return NSImage(cgImage: context.makeImage()!, size: size)
    }

    private static func blur(_ image: CGImage, radius: Double) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?
            .cropped(to: input.extent) else { return nil }
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        return context.createCGImage(output, from: input.extent)
    }

    /// The cue ball as a lit sphere, port of the Windows edition's shaded white art.
    static func cueBall(radius: Double) -> NSImage {
        let side = max(3, Int((radius * 2).rounded(.up)) + 4)
        let big = side * 3
        var pixels = [UInt8](repeating: 0, count: big * big * 4)
        let center = Double(big - 1) / 2
        let r = max(1, radius * 3)
        for py in 0..<big {
            let y = (Double(py) - center) / r
            for px in 0..<big {
                let x = (Double(px) - center) / r
                let z2 = 1 - x * x - y * y
                let offset = (py * big + px) * 4
                if z2 < 0 { continue }
                let z = z2.squareRoot()
                let light = max(0, -0.46 * x - 0.49 * y + 0.74 * z)
                let shine = exp(-((x + 0.34) * (x + 0.34) + (y + 0.40) * (y + 0.40)) / 0.038)
                let value = min(255, (157 + 96 * light + 32 * shine).rounded())
                pixels[offset] = UInt8(value)
                pixels[offset + 1] = UInt8(min(255, value + 4))
                pixels[offset + 2] = UInt8(min(255, value + 9))
                pixels[offset + 3] = 255
            }
        }
        let source = CGContext(data: &pixels, width: big, height: big, bitsPerComponent: 8,
                               bytesPerRow: big * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let target = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                               bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        target.interpolationQuality = .high
        target.draw(source.makeImage()!, in: CGRect(x: 0, y: 0, width: side, height: side))
        return NSImage(cgImage: target.makeImage()!, size: CGSize(width: side, height: side))
    }
}