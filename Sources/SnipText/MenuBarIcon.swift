import AppKit

/// The status item glyph: a reduced version of the app icon. An arrow cursor points at a block
/// of text inside three viewfinder corners. Drawn in code as a template image so it follows the
/// menu bar's appearance.
enum MenuBarIcon {
    /// `needsAttention` adds a dot in the bottom-right corner, used while screen access is missing.
    static func image(needsAttention: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            NSColor.black.set()

            // The artwork below is laid out on 18×18 but runs to the edges; shrink and center it.
            context.saveGraphicsState()
            let fit = NSAffineTransform()
            fit.translateX(by: 9, yBy: 9)
            fit.scale(by: 0.9)
            fit.translateX(by: -8.45, yBy: -9.4)
            fit.concat()

            drawCorners(in: NSRect(x: 4.6, y: 1.6, width: 12.6, height: 11), arm: 3.2)

            NSBezierPath(roundedRect: NSRect(x: 7.4, y: 4.2, width: 7.4, height: 5.6), xRadius: 1, yRadius: 1).fill()
            let lines = NSBezierPath()
            lines.move(to: NSPoint(x: 9.2, y: 5.9))
            lines.line(to: NSPoint(x: 13.1, y: 5.9))
            lines.move(to: NSPoint(x: 10.8, y: 8.1))
            lines.line(to: NSPoint(x: 13.1, y: 8.1))
            lines.lineWidth = 1.1
            lines.lineCapStyle = .round
            erase { lines.stroke() }

            drawArrow(tip: NSPoint(x: 8.6, y: 8.4))
            context.restoreGraphicsState()

            if needsAttention {
                // Bottom-right is the one corner the arrow and the text block leave free.
                let dot = NSRect(x: 12.5, y: 12.5, width: 5.5, height: 5.5)
                erase { NSBezierPath(ovalIn: dot.insetBy(dx: -1.4, dy: -1.4)).fill() }
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = needsAttention ? "SnipText – cần cấp quyền" : "SnipText"
        return image
    }

    /// Top-left, top-right and bottom-right corners; the arrow takes the place of the fourth.
    private static func drawCorners(in frame: NSRect, arm: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: frame.minX, y: frame.minY + arm))
        path.line(to: NSPoint(x: frame.minX, y: frame.minY))
        path.line(to: NSPoint(x: frame.minX + arm, y: frame.minY))
        path.move(to: NSPoint(x: frame.maxX - arm, y: frame.minY))
        path.line(to: NSPoint(x: frame.maxX, y: frame.minY))
        path.line(to: NSPoint(x: frame.maxX, y: frame.minY + arm))
        path.move(to: NSPoint(x: frame.maxX, y: frame.maxY - arm))
        path.line(to: NSPoint(x: frame.maxX, y: frame.maxY))
        path.line(to: NSPoint(x: frame.maxX - arm, y: frame.maxY))
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// An arrow cursor pointing up-right, with a thin gap cut around it like in the app icon.
    private static func drawArrow(tip: NSPoint) {
        let points: [NSPoint] = [
            NSPoint(x: 0, y: 0), NSPoint(x: 4.6, y: 8.2), NSPoint(x: 1.5, y: 7.0), NSPoint(x: 1.5, y: 11.2),
            NSPoint(x: -1.5, y: 11.2), NSPoint(x: -1.5, y: 7.0), NSPoint(x: -4.6, y: 8.2),
        ]
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach(path.line)
        path.close()
        path.lineJoinStyle = .round
        var transform = AffineTransform(translationByX: tip.x, byY: tip.y)
        transform.rotate(byDegrees: 42)
        path.transform(using: transform)

        path.lineWidth = 2.6
        erase { path.stroke() }
        path.lineWidth = 0.6
        path.fill()
        path.stroke()
    }

    private static func erase(_ draw: () -> Void) {
        NSGraphicsContext.current?.compositingOperation = .clear
        draw()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
