import KeyboardShortcuts
import ServiceManagement
import SnipTextKit
import SwiftUI

/// The Settings window, owned here rather than by a SwiftUI `Settings` scene: that scene can only
/// be opened from a view, and with the menu bar icon hidden there is none.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.bringToFront()
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Cài đặt SnipText"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        Self.window = window
        window.bringToFront()
    }
}

struct SettingsView: View {
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(PrefKey.lineBreakMode) private var lineBreakMode = LineBreakMode.keepLines
    @AppStorage(PrefKey.preferBarcode) private var preferBarcode = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Phím tắt chụp:", name: .capture)

            Picker("Xuống dòng:", selection: $lineBreakMode) {
                ForEach(LineBreakMode.allCases) { Text($0.title).tag($0) }
            }

            Toggle("Ưu tiên copy mã QR khi vùng chọn có cả chữ và mã", isOn: $preferBarcode)

            Toggle("Mở cùng macOS", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Toggle("Hiện icon trên thanh menu", isOn: $showMenuBarIcon)

            // The menu's Quit is gone with the icon, and the app has no main menu for ⌘Q.
            if !showMenuBarIcon {
                Button("Thoát SnipText") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}
