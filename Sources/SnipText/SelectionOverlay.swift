import AppKit
import SnipTextKit

/// Full-screen region picker. With `snapshots` it is drawn over frozen images of every display;
/// without them the screen stays live under a dim layer and the region is captured after the drag.
/// Drag to select, Esc or right-click to cancel.
@MainActor
final class SelectionOverlay {
    /// A finished drag: the display it was on, and the region in points, origin top-left.
    private struct Pick {
        var displayID: CGDirectDisplayID
        var rect: CGRect
        var pointSize: CGSize
    }

    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<Pick?, Never>?
    /// The app the user was working in; focus goes back to it when the overlay closes.
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?

    private static var active: SelectionOverlay?

    /// Returns the selected region, or nil if cancelled.
    static func selectRegion(from snapshots: [DisplaySnapshot]?) async throws -> CGImage? {
        let overlay = SelectionOverlay()
        active = overlay
        let pick = await withCheckedContinuation { continuation in
            overlay.continuation = continuation
            overlay.show(snapshots)
        }
        active = nil
        guard let pick else { return nil }
        if let snapshots {
            guard let image = snapshots.first(where: { $0.displayID == pick.displayID })?.image else { return nil }
            return CaptureService.crop(image, toPoints: pick.rect, pointSize: pick.pointSize)
        }
        return try await CaptureService.captureRegion(onDisplay: pick.displayID, rect: pick.rect)
    }

    /// Closes the open overlay as if the user pressed Esc (used by the self-test).
    static func cancelActive() {
        active?.finish(with: nil)
    }

    private func show(_ snapshots: [DisplaySnapshot]?) {
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            var image: CGImage?
            if let snapshots {
                guard let snapshot = snapshots.first(where: { $0.displayID == id }) else { continue }
                image = snapshot.image
            }
            let view = SelectionView(image: image)
            view.onFinish = { [weak self] rect in
                self?.finish(with: rect.map { Pick(displayID: id, rect: $0, pointSize: screen.frame.size) })
            }
            let window = OverlayWindow(screen: screen, view: view, transparent: image == nil)
            windows.append(window)
        }
        guard !windows.isEmpty else { return finish(with: nil) }

        // A display added, removed or rearranged leaves the overlay windows (and any snapshot)
        // out of step with the screens, so cancel and let the user start again.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(with: nil) }
        }

        // The overlay must be active to receive Esc, which takes focus from the user's app.
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost == .current ? nil : frontmost
        NSApp.activate()
        let mouseScreen = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows[0]
        windows.forEach { $0.orderFrontRegardless() }
        mouseScreen.makeKey()
        // Show the crosshair right away, before the mouse first moves.
        NSCursor.crosshair.set()
    }

    private func finish(with pick: Pick?) {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()
        if let previousApp {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        continuation?.resume(returning: pick)
        continuation = nil
    }
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen, view: NSView, transparent: Bool) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = !transparent
        backgroundColor = transparent ? .clear : .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = view
    }

    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    /// Called with the selected rect in points (origin top-left), or nil when cancelled.
    var onFinish: ((CGRect?) -> Void)?

    /// The frozen frame to draw; nil draws nothing, so the live screen shows through.
    private let image: CGImage?
    private var dragStart: NSPoint?
    private var selection: NSRect?

    init(image: CGImage?) {
        self.image = image
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(point.x - start.x), height: abs(point.y - start.y))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        // A click without a real drag keeps the overlay open.
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            self.selection = nil
            needsDisplay = true
            return
        }
        onFinish?(CaptureService.topLeftRect(selection, inHeight: bounds.height))
    }

    override func rightMouseDown(with event: NSEvent) { onFinish?(nil) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let image {
            context.draw(image, in: bounds)
        }

        // Dim everything outside the selection.
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let selection { dim.addRect(selection) }
        context.addPath(dim)
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fillPath(using: .evenOdd)

        if let selection {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
            drawSizeLabel(for: selection)
        } else {
            drawHint()
        }
    }

    private func drawSizeLabel(for selection: NSRect) {
        drawPill("\(Int(selection.width)) × \(Int(selection.height))",
                 at: NSPoint(x: selection.minX, y: selection.minY - 26), clampTo: bounds)
    }

    private func drawHint() {
        let text = "Kéo để chọn vùng có chữ  ·  Esc để huỷ"
        let size = pillSize(text)
        drawPill(text, at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 80), clampTo: bounds)
    }

    private static let pillAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private func pillSize(_ text: String) -> NSSize {
        let size = (text as NSString).size(withAttributes: Self.pillAttributes)
        return NSSize(width: size.width + 16, height: size.height + 8)
    }

    private func drawPill(_ text: String, at origin: NSPoint, clampTo area: NSRect) {
        let size = pillSize(text)
        var frame = NSRect(origin: origin, size: size)
        frame.origin.x = min(max(frame.minX, area.minX + 4), area.maxX - size.width - 4)
        if frame.minY < area.minY + 4 { frame.origin.y = area.minY + 4 }
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: frame, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        (text as NSString).draw(at: NSPoint(x: frame.minX + 8, y: frame.minY + 4), withAttributes: Self.pillAttributes)
    }

    // MARK: Preview support

    /// Renders the overlay with a given selection, for visual checks.
    func renderPreview(size: CGSize, selection: NSRect?) -> NSBitmapImageRep? {
        frame = NSRect(origin: .zero, size: size)
        self.selection = selection
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
