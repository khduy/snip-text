import KeyboardShortcuts
import ServiceManagement
import SnipTextKit
import SwiftUI

/// The Settings window, owned here rather than by a SwiftUI `Settings` scene: that scene can only
/// be opened from a view, and with the menu bar icon hidden there is none.
@MainActor
enum SettingsWindow {
    private(set) static var window: NSWindow?

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

    static func close() {
        window?.close()
    }
}

struct SettingsView: View {
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(PrefKey.lineBreakMode) private var lineBreakMode = LineBreakMode.keepLines
    @AppStorage(PrefKey.preferBarcode) private var preferBarcode = false
    @AppStorage(PrefKey.freezeScreen) private var freezeScreen = false
    @AppStorage(PrefKey.saveHistory) private var saveHistory = true
    /// Read again whenever the window comes forward: the user can switch it off in
    /// System Settings while this window stays open in the background.
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            form
            // The app has no main menu, so ⌘Q and ⌘W only work through these buttons.
            HStack {
                Button("Thoát SnipText") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                Spacer()
                Button("Đóng") { SettingsWindow.close() }
                    .keyboardShortcut("w")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 460)
        .fixedSize()
        // Only this window: the capture overlay also becomes key, and the window is kept (and so
        // keeps listening) after it closes.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .filter { $0.object as? NSWindow === SettingsWindow.window }) { _ in
            loginStatus = SMAppService.mainApp.status
            HotkeyStatus.shared.refresh()
        }
    }

    private var form: some View {
        // Capturing, then what lands on the clipboard, then the app itself.
        Form {
            Section {
                KeyboardShortcuts.Recorder("Phím tắt chụp:", name: .capture)
                if HotkeyStatus.shared.isTaken {
                    warning("Phím tắt này đang bị app khác dùng. Chọn phím khác, hoặc thoát app kia rồi",
                            action: "Thử lại") { HotkeyStatus.shared.refresh() }
                }
                Toggle("Đóng băng màn hình khi chụp", isOn: $freezeScreen)
            }

            Section {
                Picker("Xuống dòng:", selection: $lineBreakMode) {
                    ForEach(LineBreakMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Ưu tiên copy mã QR khi vùng chọn có cả chữ và mã", isOn: $preferBarcode)
                Toggle("Lưu lịch sử", isOn: $saveHistory)
            }

            Section {
                Toggle("Mở cùng macOS", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    // A closure, not the method itself: passing the method crashes Swift 6.1's
                    // compiler (Xcode 16.4, used in CI) while emitting its @isolated(any) thunk.
                    set: { enabled in setLaunchAtLogin(enabled) }))
                if loginStatus == .requiresApproval {
                    warning("macOS cần bạn cho phép SnipText trong Mục đăng nhập.", action: "Mở Cài đặt") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } else if let loginError {
                    warning(loginError)
                }
                Toggle("Hiện icon trên thanh menu", isOn: $showMenuBarIcon)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Không đổi được: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }

    private func warning(_ message: String, action: String? = nil, perform: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 4) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
            if let action {
                Button(action, action: perform).buttonStyle(.link)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
