import KeyboardShortcuts
import ServiceManagement
import SnipTextKit
import SwiftUI

struct SettingsView: View {
    /// The window SwiftUI put this view in, kept so the menu can bring it front on later opens.
    static weak var window: NSWindow?

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

            Section("Quyền chụp màn hình") {
                LabeledContent("Trạng thái:") {
                    if Permissions.hasScreenCaptureAccess {
                        Label("Đã cấp", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Chưa có hiệu lực", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                HStack {
                    Button("Cấp quyền") { Permissions.requestAccess() }
                    Button("Khởi động lại") { Permissions.relaunch() }
                    Button("Đặt lại quyền") { Permissions.resetPermission() }
                }
            }
        }
        .formStyle(.grouped)
        .background(WindowReader { window in
            Self.window = window
            window.bringToFront()
        })
        .frame(width: 460)
        .fixedSize()
    }
}

/// Reports the window a SwiftUI view ends up in.
private struct WindowReader: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { ReaderView(onAttach: onAttach) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let onAttach: (NSWindow) -> Void

        init(onAttach: @escaping (NSWindow) -> Void) {
            self.onAttach = onAttach
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onAttach(window) }
        }
    }
}
