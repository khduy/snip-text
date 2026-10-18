// Draws the SnipText app icon: a blue rounded square with viewfinder corners around
// three lines of "text". Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// macOS icon grid: 824pt body centered on a 1024pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Soft drop shadow under the body.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.3))
context.addPath(bodyPath)
context.setFillColor(color(0x3A4FD8))
context.fillPath()
context.restoreGState()

// Gradient fill, lighter at the top.
context.saveGState()
context.addPath(bodyPath)
context.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [color(0x5AA2FF), color(0x3B4BD6)] as CFArray,
    locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
context.restoreGState()

// Viewfinder corners.
let frame = body.insetBy(dx: 150, dy: 150)
let arm: CGFloat = 120
context.setStrokeColor(color(0xFFFFFF))
context.setLineWidth(48)
context.setLineCap(.round)
context.setLineJoin(.round)
let corners: [(CGPoint, CGFloat, CGFloat)] = [
    (CGPoint(x: frame.minX, y: frame.maxY), 1, -1),
    (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),
    (CGPoint(x: frame.minX, y: frame.minY), 1, 1),
    (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),
]
for (point, dx, dy) in corners {
    context.move(to: CGPoint(x: point.x, y: point.y + dy * arm))
    context.addLine(to: point)
    context.addLine(to: CGPoint(x: point.x + dx * arm, y: point.y))
}
context.strokePath()

// Three lines of "text" inside the frame.
let textArea = frame.insetBy(dx: 95, dy: 120)
let lineHeight: CGFloat = 44
let widths: [CGFloat] = [1.0, 0.78, 0.9]
for (index, fraction) in widths.enumerated() {
    let y = textArea.maxY - lineHeight - CGFloat(index) * (textArea.height - lineHeight) / CGFloat(widths.count - 1)
    let line = CGRect(x: textArea.minX, y: y, width: textArea.width * fraction, height: lineHeight)
    context.addPath(CGPath(roundedRect: line, cornerWidth: lineHeight / 2, cornerHeight: lineHeight / 2, transform: nil))
}
context.setFillColor(color(0xFFFFFF, alpha: 0.92))
context.fillPath()

let image = NSBitmapImageRep(cgImage: context.makeImage()!)
try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
