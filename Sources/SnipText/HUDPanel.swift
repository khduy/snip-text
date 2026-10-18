import AppKit
import SwiftUI

/// Small floating toast shown near the top of the active screen. Never takes focus.
@MainActor
final class HUDPanel {
    static let shared = HUDPanel()

    typealias Action = (title: String, perform: () -> Void)

    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    private init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(_ message: String, action: Action? = nil) {
        let view = HUDView(message: message, action: action.map { action in
            (action.title, { [weak self] in
                action.perform()
                self?.show("Đã copy")
            })
        })
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.maxY - panel.frame.height - 24))
        }
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [panel] in
            try? await Task.sleep(for: .seconds(action == nil ? 1.5 : 4))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

private struct HUDView: View {
    let message: String
    let action: (String, () -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.title3)
            Text(message)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: 360, alignment: .leading)
            if let (title, perform) = action {
                Button(title, action: perform)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }
}
