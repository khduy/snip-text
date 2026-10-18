import KeyboardShortcuts
import SnipTextKit
import SwiftUI

@main
struct SnipTextApp: App {
    @State private var controller: AppController

    init() {
        // Child process spawned by Permissions.checkAccessInFreshProcess(): answer and quit
        // before any UI or hotkey is set up.
        if CommandLine.arguments.contains(Permissions.checkAccessArgument) {
            print(CGPreflightScreenCaptureAccess() ? "1" : "0")
            exit(0)
        }
        _controller = State(initialValue: AppController())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            // Access only changes across a relaunch (see Permissions), so reading it here is enough.
            Image(nsImage: MenuBarIcon.image(needsAttention: !Permissions.hasScreenCaptureAccess))
        }

        Settings {
            SettingsView()
        }
    }
}

private struct MenuContent: View {
    let controller: AppController
    @Environment(\.openSettings) private var openSettings

    /// How many captures sit directly in the menu; the rest go under "Tất cả lịch sử".
    private static let recentCount = 3

    var body: some View {
        if !Permissions.hasScreenCaptureAccess {
            Button {
                OnboardingWindow.show(step: .permission)
            } label: {
                Label("Cấp quyền ghi màn hình…", systemImage: "exclamationmark.triangle")
            }
            Divider()
        }

        Button("Lấy chữ từ màn hình") { controller.capture() }
            .globalKeyboardShortcut(.capture)

        // A titled Section draws a separator on each side itself, so no Divider goes next to it.
        let items = controller.history.items
        if items.isEmpty {
            Divider()
        } else {
            Section("Gần đây") {
                ForEach(Array(items.prefix(Self.recentCount).enumerated()), id: \.element.id) { index, item in
                    historyButton(item)
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
                Menu("Tất cả lịch sử") {
                    ForEach(items.prefix(20)) { historyButton($0) }
                    Divider()
                    Button("Xoá lịch sử") { controller.history.clear() }
                }
            }
        }

        Button("Cài đặt…") {
            openSettings()
            // On first open the window does not exist yet; SettingsView brings it front once attached.
            SettingsView.window?.bringToFront()
        }
        .keyboardShortcut(",")

        Button("Thoát SnipText") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// The icon tells a QR read from text, since the snippet alone often cannot.
    private func historyButton(_ item: HistoryItem) -> some View {
        Button {
            controller.copy(item)
        } label: {
            Label(TextFormatter.snippet(item.primaryContent, limit: 44),
                  systemImage: item.text.isEmpty ? "qrcode" : "text.alignleft")
        }
    }
}

extension NSWindow {
    /// A menu bar app is not active when its menu is used. The non-deprecated `NSApp.activate()`
    /// is turned down there (tested: the window shows but the other app keeps the keyboard),
    /// so this keeps the deprecated call on purpose.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}
