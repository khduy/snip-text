// Draws the SnipText app icon: the dark glyph from scripts/icon-glyph.png (black artwork on
// white) on a white rounded square. Usage: swift scripts/make-icon.swift <glyph.png> <output.png>
import AppKit

let size: CGFloat = 1024
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    print("usage: make-icon.swift <glyph.png> <output.png>")
    exit(1)
}
let (glyphPath, output) = (arguments[0], arguments[1])

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Turns the artwork into a coverage mask (white = paint) and finds the drawn area.
/// Darkness becomes coverage, so the grey speed lines stay lighter; near-white noise is dropped.
func makeMask(from url: URL) -> (mask: CGImage, bounds: CGRect) {
    guard let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("cannot read \(url.path)")
        exit(1)
    }
    let width = source.width, height = source.height
    var pixels = [UInt8](repeating: 0, count: width * height)
    let gray = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    gray.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height {
        for x in 0..<width {
            let i = y * width + x
            let darkness = (255 - Double(pixels[i])) / 255
            let coverage = min(max((darkness - 0.06) / 0.84, 0), 1)
            pixels[i] = UInt8(coverage * 255)
            if coverage > 0.1 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    let mask = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        .makeImage()!
    // Rows in the buffer run top-down; CG rects are bottom-up.
    let bounds = CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    return (mask, bounds)
}

let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// macOS icon grid: 824pt body centered on a 1024pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Soft drop shadow under the body.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.3))
context.addPath(bodyPath)
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.restoreGState()

// Barely-there gradient so the white body does not look flat next to other icons.
context.saveGState()
context.addPath(bodyPath)
context.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [color(0xFFFFFF), color(0xECECEF)] as CFArray,
    locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
context.restoreGState()

// The glyph, scaled to fit the body's inner area and centered on what is actually drawn.
let (mask, drawn) = makeMask(from: URL(fileURLWithPath: glyphPath))
let area = body.insetBy(dx: 120, dy: 120)
let scale = min(area.width / drawn.width, area.height / drawn.height)
let target = CGRect(
    x: area.midX - (drawn.midX - 0) * scale,
    y: area.midY - (drawn.midY - 0) * scale,
    width: CGFloat(mask.width) * scale,
    height: CGFloat(mask.height) * scale)
context.saveGState()
context.clip(to: target, mask: mask)
context.setFillColor(color(0x1C1C1E))
context.fill(target)
context.restoreGState()

let image = NSBitmapImageRep(cgImage: context.makeImage()!)
try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
