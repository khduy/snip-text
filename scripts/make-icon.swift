// Draws the SnipText app icon in vector: on a graphite rounded square, an arrow cursor points at
// a yellow, highlighted block of text inside three viewfinder corners. Same geometry as the menu
// bar glyph (Sources/SnipText/MenuBarIcon.swift). Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
guard let output = CommandLine.arguments.dropFirst().first else {
    print("usage: make-icon.swift <output.png>")
    exit(1)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// MARK: Glyph, on the menu bar glyph's 18-unit grid (y down)

let cornerWidth: CGFloat = 1.25
let corners: CGPath = {
    let frame = CGRect(x: 4.6, y: 1.6, width: 12.6, height: 11)
    let arm: CGFloat = 3.2
    let path = CGMutablePath()
    path.addLines(between: [CGPoint(x: frame.minX, y: frame.minY + arm), CGPoint(x: frame.minX, y: frame.minY),
                            CGPoint(x: frame.minX + arm, y: frame.minY)])
    path.addLines(between: [CGPoint(x: frame.maxX - arm, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                            CGPoint(x: frame.maxX, y: frame.minY + arm)])
    path.addLines(between: [CGPoint(x: frame.maxX, y: frame.maxY - arm), CGPoint(x: frame.maxX, y: frame.maxY),
                            CGPoint(x: frame.maxX - arm, y: frame.maxY)])
    return path.copy(strokingWithWidth: cornerWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
}()

let block = CGPath(roundedRect: CGRect(x: 7.4, y: 4.2, width: 7.4, height: 5.6), cornerWidth: 1, cornerHeight: 1, transform: nil)

let textLines: CGPath = {
    let path = CGMutablePath()
    path.addLines(between: [CGPoint(x: 9.2, y: 5.9), CGPoint(x: 13.1, y: 5.9)])
    path.addLines(between: [CGPoint(x: 10.8, y: 8.1), CGPoint(x: 13.1, y: 8.1)])
    return path.copy(strokingWithWidth: 1.0, lineCap: .round, lineJoin: .round, miterLimit: 10)
}()

/// Arrow cursor pointing up-right, its tip on the block's lower-left corner.
let arrow: CGPath = {
    let points = [(0.0, 0.0), (4.6, 8.2), (1.5, 7.0), (1.5, 11.2), (-1.5, 11.2), (-1.5, 7.0), (-4.6, 8.2)]
        .map { CGPoint(x: $0.0, y: $0.1) }
    let transform = CGAffineTransform(translationX: 8.6, y: 8.4).rotated(by: 42 * .pi / 180).scaledBy(x: 0.62, y: 0.62)
    let path = CGMutablePath()
    path.addLines(between: points, transform: transform)
    path.closeSubpath()
    // Round the arrow's corners slightly, as the menu bar glyph does with its stroke join.
    return path.copy(strokingWithWidth: 0.4, lineCap: .round, lineJoin: .round, miterLimit: 10)
        .union(path)
}()
let arrowGap = arrow.copy(strokingWithWidth: 1.2, lineCap: .round, lineJoin: .round, miterLimit: 10)

// MARK: Canvas

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
context.setFillColor(color(0x1E1E21))
context.fillPath()
context.restoreGState()

// Graphite gradient, lighter at the top.
context.saveGState()
context.addPath(bodyPath)
context.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [color(0x3A3A3F), color(0x1E1E21)] as CFArray,
    locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
context.restoreGState()

// A faint inner edge keeps the dark body from melting into a dark Dock or Finder window.
context.saveGState()
context.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183.5, cornerHeight: 183.5, transform: nil))
context.setStrokeColor(color(0xFFFFFF, alpha: 0.1))
context.setLineWidth(3)
context.strokePath()
context.restoreGState()

// Fit the glyph's drawn bounds into the body's inner area and center them. The grid is y-down,
// so flip it on the way in.
let drawn = corners.boundingBoxOfPath.union(block.boundingBoxOfPath).union(arrowGap.boundingBoxOfPath)
let unit = 560 / max(drawn.width, drawn.height)
context.translateBy(x: body.midX, y: body.midY)
context.scaleBy(x: unit, y: -unit)
context.translateBy(x: -drawn.midX, y: -drawn.midY)

// Draw the glyph in its own layer so the gap around the arrow cuts through the glyph only.
context.beginTransparencyLayer(auxiliaryInfo: nil)
context.addPath(corners)
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.addPath(block)
context.setFillColor(color(0xFFC93C))
context.fillPath()
context.addPath(textLines)
context.setFillColor(color(0x2A2A2E))
context.fillPath()
context.setBlendMode(.clear)
context.addPath(arrowGap)
context.fillPath()
context.setBlendMode(.normal)
context.addPath(arrow)
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.endTransparencyLayer()

let image = NSBitmapImageRep(cgImage: context.makeImage()!)
try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
