import AppKit

/// The status item glyph: a dashed selection marquee around a text cursor.
/// Drawn in code as a template image so it follows the menu bar's appearance.
enum MenuBarIcon {
    /// `needsAttention` adds a dot in the corner, used while screen access is missing.
    static func image(needsAttention: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()

            let marquee = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 2.75, width: 14.5, height: 12.5),
                                       xRadius: 2.5, yRadius: 2.5)
            marquee.lineWidth = 1.5
            marquee.setLineDash([2.6, 1.9], count: 2, phase: 0)
            marquee.stroke()

            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 9, y: 6))
            cursor.line(to: NSPoint(x: 9, y: 12))
            for y in [6.0, 12.0] {
                cursor.move(to: NSPoint(x: 7, y: y))
                cursor.line(to: NSPoint(x: 11, y: y))
            }
            cursor.lineWidth = 1.5
            cursor.lineCapStyle = .round
            cursor.stroke()

            if needsAttention {
                let dot = NSRect(x: 11.5, y: 0.5, width: 6.5, height: 6.5)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = needsAttention ? "SnipText – cần cấp quyền" : "SnipText"
        return image
    }
}
