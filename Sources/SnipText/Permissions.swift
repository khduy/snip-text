import AppKit
import PermissionFlow

/// Screen Recording permission handling, including the usual ways it silently fails
/// for apps that are not notarized: stale TCC entries, app translocation, no relaunch.
@MainActor
enum Permissions {
    static var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// A quarantined app launched from Downloads runs from a random read-only path,
    /// so permissions granted to it do not stick.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    /// Returns true when capturing can go ahead; otherwise walks the user through granting access.
    static func ensureScreenCaptureAccess() -> Bool {
        if isTranslocated {
            showTranslocationAlert()
            return false
        }
        if hasScreenCaptureAccess { return true }
        OnboardingWindow.show(step: .permission)
        return false
    }

    private static let permissionFlow = PermissionFlow.makeController(
        configuration: .init(requiredAppURLs: [Bundle.main.bundleURL]))

    private static let promptedKey = "screenCapturePrompted"

    /// Whether macOS's own permission prompt has been used up. It shows once per TCC entry, so
    /// this can only be a best guess: an entry left by an older build is not visible to the app.
    static var hasPromptedForAccess: Bool {
        get { UserDefaults.standard.bool(forKey: promptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: promptedKey) }
    }

    /// The first time, shows only macOS's prompt: its "Open System Settings" button opens the
    /// pane with SnipText already listed, so the user just flips the switch. Opening Settings
    /// at the same time would hide the prompt behind it until Settings is closed.
    /// After that, opens Screen Recording settings with a floating panel next to it, from which
    /// the user drags SnipText into the list.
    static func requestAccess(from sourceFrame: CGRect? = nil) {
        guard hasPromptedForAccess else {
            hasPromptedForAccess = true
            // Off the main thread in case the call waits for the prompt to be answered.
            Task.detached { _ = CGRequestScreenCaptureAccess() }
            return
        }
        permissionFlow.authorize(
            pane: .screenRecording,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: sourceFrame)
    }

    static func closePermissionPanel() {
        permissionFlow.closePanel()
    }

    nonisolated static let checkAccessArgument = "--check-screen-access"

    /// A running process keeps seeing the permission state it started with, so ask a fresh
    /// child process instead. It is attributed to SnipText, so it sees SnipText's entry.
    nonisolated static func checkAccessInFreshProcess() async -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = [checkAccessArgument]
        process.standardOutput = pipe
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(decoding: output, as: UTF8.self).hasPrefix("1"))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    /// Removes this app's (possibly stale) Screen Recording entry, then relaunches into the
    /// permission step, where macOS can prompt again and the user can switch it on.
    /// If tccutil fails, says so and stays put: a relaunch would land on the same stale entry.
    static func resetPermission() async {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        let status: Int32? = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
        guard status == 0 else {
            showResetFailedAlert()
            return
        }
        hasPromptedForAccess = false
        relaunch(arguments: [OnboardingWindow.permissionStepArgument])
    }

    private static func showResetFailedAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Không đặt lại được quyền"
        alert.informativeText = """
            Hãy mở Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Ghi màn hình, xoá SnipText khỏi \
            danh sách bằng nút "−", rồi mở lại SnipText.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func relaunch(arguments extraArguments: [String] = []) {
        // Quit first, then reopen once this process is gone; two instances would fight over the
        // global hotkey. If it is somehow still running after 10 s, nothing is opened.
        let script = """
            pid=$1; shift; i=0
            while kill -0 "$pid" 2>/dev/null; do
              [ $i -ge 100 ] && exit 1
              sleep 0.1; i=$((i + 1))
            done
            /usr/bin/open -n "$0" --args "$@"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundlePath,
                             String(ProcessInfo.processInfo.processIdentifier)] + extraArguments
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func showTranslocationAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Hãy chuyển SnipText vào thư mục Applications"
        alert.informativeText = """
            macOS đang chạy SnipText từ một bản tạm vì app còn cờ quarantine. Quyền chụp màn hình \
            sẽ không được giữ. Kéo SnipText vào Applications rồi chạy trong Terminal:

            xattr -dr com.apple.quarantine /Applications/SnipText.app
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
