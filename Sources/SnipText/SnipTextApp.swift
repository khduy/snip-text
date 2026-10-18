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
        MenuBarExtra("SnipText", systemImage: "text.viewfinder") {
            MenuContent(controller: controller)
        }

        Settings {
            SettingsView()
        }
    }
}

private struct MenuContent: View {
    let controller: AppController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Chụp lấy chữ") { controller.capture() }
            .globalKeyboardShortcut(.capture)

        Menu("Lịch sử") {
            if controller.history.items.isEmpty {
                Text("Chưa có gì")
            } else {
                ForEach(controller.history.items.prefix(10)) { item in
                    Button(snippet(item.primaryContent)) { controller.copy(item.primaryContent) }
                }
                Divider()
                Button("Xoá lịch sử") { controller.history.clear() }
            }
        }

        Divider()

        Button("Hướng dẫn bắt đầu…") { OnboardingWindow.show(step: .welcome) }

        Button("Cài đặt…") {
            openSettings()
            // On first open the window does not exist yet; SettingsView brings it front once attached.
            SettingsView.window?.bringToFront()
        }
        .keyboardShortcut(",")

        Button("Thoát SnipText") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func snippet(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 40 ? flat.prefix(40) + "…" : flat
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
