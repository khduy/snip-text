import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

// Layout and flow follow Gõ Nhanh's onboarding (github.com/khaphanspace/gonhanh.org,
// platforms/macos/OnboardingView.swift): fixed-height content, footer with step dots and
// buttons, a "granted → restart" step. Opening Settings goes through PermissionFlow.

@MainActor
@Observable
final class OnboardingModel {
    enum Step: CaseIterable {
        case welcome, permission, granted, ready

        /// Position in the step dots; "granted" is the tail of the permission step.
        var dotIndex: Int {
            switch self {
            case .welcome: 0
            case .permission, .granted: 1
            case .ready: 2
            }
        }
    }

    var step: Step {
        didSet { step == .permission ? startWatchingPermission() : stopWatchingPermission() }
    }
    var onTryNow: () -> Void = {}
    var onClose: () -> Void = {}
    private(set) var hasPrompted = Permissions.hasPromptedForAccess

    @ObservationIgnored private var watchTask: Task<Void, Never>?

    init(step: Step) {
        self.step = step
        if step == .permission { startWatchingPermission() }
    }

    func next() {
        step = Permissions.hasScreenCaptureAccess ? .ready : .permission
    }

    func requestAccess() {
        Permissions.requestAccess(from: NSApp.keyWindow?.frame)
        hasPrompted = Permissions.hasPromptedForAccess
    }

    func restart() {
        Permissions.relaunch(arguments: [OnboardingWindow.readyStepArgument])
    }

    func tryNow() {
        finish()
        onTryNow()
    }

    func finish() {
        OnboardingWindow.isCompleted = true
        stopWatchingPermission()
        onClose()
    }

    /// Screen Recording grants are not visible to a process that is already running,
    /// so poll through a fresh child process (Gõ Nhanh can poll AXIsProcessTrusted directly).
    private func startWatchingPermission() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                let granted = await Permissions.checkAccessInFreshProcess()
                // The child process keeps running after a cancel; ignore its late answer.
                guard !Task.isCancelled, let self, self.step == .permission else { return }
                if granted {
                    Permissions.closePermissionPanel()
                    NSApp.activate()
                    self.step = .granted
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Also closes PermissionFlow's floating panel, so going Back or closing the window
    /// does not leave it tracking System Settings.
    func stopWatchingPermission() {
        watchTask?.cancel()
        watchTask = nil
        Permissions.closePermissionPanel()
    }
}

@MainActor
enum OnboardingWindow {
    static let readyStepArgument = "--onboarding-ready"
    static let permissionStepArgument = "--onboarding-permission"
    private static let completedKey = "onboardingCompleted"

    private static var window: NSWindow?
    private static var model: OnboardingModel?
    private static var closeObserver: NSObjectProtocol?
    static var onTryNow: () -> Void = {}

    static var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    /// Decides at launch whether to show onboarding, and at which step.
    static func showIfNeeded() {
        let arguments = CommandLine.arguments
        if arguments.contains(readyStepArgument) {
            show(step: .ready)
        } else if arguments.contains(permissionStepArgument) {
            show(step: .permission)
        } else if !isCompleted {
            show(step: Permissions.hasScreenCaptureAccess ? .ready : .welcome)
        }
    }

    static func show(step: OnboardingModel.Step) {
        if let window, let model {
            model.step = step
            window.bringToFront()
            return
        }

        let model = OnboardingModel(step: step)
        let hosting = NSHostingController(rootView: OnboardingView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnipText"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        // Weak: the window owns the model through its hosting controller.
        model.onClose = { [weak window] in window?.close() }
        model.onTryNow = { onTryNow() }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                Self.model?.stopWatchingPermission()
                if let closeObserver = Self.closeObserver {
                    NotificationCenter.default.removeObserver(closeObserver)
                }
                Self.closeObserver = nil
                Self.window = nil
                Self.model = nil
            }
        }

        Self.window = window
        Self.model = model
        window.bringToFront()
    }
}

struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            content.frame(height: 320)
            Divider()
            footer
        }
        .frame(width: 440)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .permission: PermissionStep(hasPrompted: model.hasPrompted)
        case .granted: GrantedStep()
        case .ready: ReadyStep()
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == model.step.dotIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            switch model.step {
            case .welcome:
                Button("Tiếp tục") { model.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .permission:
                Button("Quay lại") { model.step = .welcome }
                Button(model.hasPrompted ? "Mở Cài đặt" : "Cấp quyền") { model.requestAccess() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .granted:
                Button("Khởi động lại") { model.restart() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .ready:
                Button("Xong") { model.finish() }
                Button("Thử ngay") { model.tryNow() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        StepLayout {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 80, height: 80)

            Text("Chào mừng đến với SnipText")
                .font(.title2.bold())

            Text("Kéo chọn vùng màn hình, chữ được copy ngay vào clipboard. Nhận dạng offline, hỗ trợ tiếng Việt và English.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Phím tắt:")
                KeyboardShortcuts.Recorder(for: .capture)
            }
            .padding(.top, 4)
        }
    }
}

private struct PermissionStep: View {
    let hasPrompted: Bool

    var body: some View {
        StepLayout {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Cấp quyền ghi màn hình")
                .font(.title2.bold())

            Text("SnipText cần quyền này để nhìn thấy vùng bạn chọn. Ảnh chỉ được xử lý trên máy.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                if hasPrompted {
                    // macOS skips its prompt if it has asked before, so always offer the way around it.
                    Label("Chọn \"Mở Cài đặt hệ thống\" trong hộp thoại của macOS", systemImage: "1.circle.fill")
                    Label("Không thấy hộp thoại? Bấm \"Mở Cài đặt\"", systemImage: "2.circle.fill")
                    Label("Bật công tắc cạnh SnipText (hoặc kéo từ khung nổi vào)", systemImage: "3.circle.fill")
                } else {
                    Label("Bấm \"Cấp quyền\"", systemImage: "1.circle.fill")
                    Label("Chọn \"Mở Cài đặt hệ thống\" trong hộp thoại của macOS", systemImage: "2.circle.fill")
                    Label("Bật công tắc cạnh SnipText", systemImage: "3.circle.fill")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            HStack(spacing: 4) {
                Text("Đã bật mà không nhận?")
                Button("Đặt lại quyền") { Task { await Permissions.resetPermission() } }
                    .buttonStyle(.link)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

private struct GrantedStep: View {
    var body: some View {
        StepLayout {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Đã cấp quyền")
                .font(.title2.bold())

            Text("Nhấn \"Khởi động lại\" để áp dụng.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ReadyStep: View {
    var body: some View {
        StepLayout {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Sẵn sàng hoạt động")
                .font(.title2.bold())

            Text(KeyboardShortcuts.getShortcut(for: .capture)?.description ?? "Chưa đặt phím tắt")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            Text("Bấm phím tắt bất cứ lúc nào để lấy chữ. SnipText nằm trên thanh menu.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StepLayout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            content
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
