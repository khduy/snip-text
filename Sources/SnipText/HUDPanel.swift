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

    func show(_ title: String, detail: String? = nil, symbol: String, action: Action? = nil) {
        let view = HUDView(title: title, detail: detail, symbol: symbol, action: action)
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
            // Long enough to read the preview; longer still when there is a button to reach.
            try? await Task.sleep(for: .seconds(action != nil ? 4 : detail != nil ? 2.5 : 1.5))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

struct HUDView: View {
    let title: String
    let detail: String?
    let symbol: String
    let action: HUDPanel.Action?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 340, alignment: .leading)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize()
    }
}
