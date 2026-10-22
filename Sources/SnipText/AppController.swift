import AppKit
import KeyboardShortcuts
import Observation
import OSLog
import SnipTextKit

private let logger = Logger(subsystem: "io.github.khduy.sniptext", category: "capture")

@MainActor
@Observable
final class AppController {
    let history = HistoryStore()
    private(set) var isCapturing = false

    init() {
        KeyboardShortcuts.onKeyUp(for: .capture) { [weak self] in
            self?.capture()
        }
        HotkeyStatus.shared.refresh()
        Task.detached(priority: .utility) { await OCRService.warmUp() }

        if SelfTest.isRequested {
            SelfTest.run()
        } else {
            OnboardingWindow.onTryNow = { [weak self] in self?.capture() }
            OnboardingWindow.showIfNeeded()
            if HotkeyStatus.shared.isTaken {
                // After launch finishes, so the HUD is not shown before the app is up.
                Task {
                    HUDPanel.shared.show("Phím tắt đang bị app khác dùng",
                                         detail: "Đổi phím tắt trong Cài đặt SnipText.",
                                         symbol: "keyboard.badge.exclamationmark")
                }
            }
        }
    }

    func capture() {
        guard !isCapturing else { return }
        guard Permissions.ensureScreenCaptureAccess() else { return }

        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                var snapshots: [DisplaySnapshot]?
                if Preferences.freezeScreen {
                    snapshots = try await CaptureService.captureDisplays()
                }
                guard let image = try await SelectionOverlay.selectRegion(from: snapshots) else { return }
                if Preferences.saveLastCapture {
                    CaptureService.saveForDiagnostics(image)
                }
                let result = try await OCRService.recognize(
                    image, correctsLanguage: Preferences.lineBreakMode != .preserveIndent)
                logger.notice("""
                    captured \(image.width)x\(image.height), \
                    \(result.fragments.count) text fragments, \(result.barcodes.count) barcodes
                    """)
                handle(result)
            } catch CaptureError.displayUnavailable {
                HUDPanel.shared.show("Màn hình vừa bị ngắt kết nối",
                                     detail: "Chọn lại vùng trên màn hình đang dùng.",
                                     symbol: "display.trianglebadge.exclamationmark")
            } catch {
                logger.error("capture failed: \(error)")
                HUDPanel.shared.show("Không chụp được màn hình",
                                     detail: "Thử lại. Nếu vẫn lỗi, kiểm tra quyền trong Cài đặt.",
                                     symbol: "exclamationmark.triangle")
            }
        }
    }

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Copies a history item, with the same confirmation as a fresh capture.
    func copy(_ item: HistoryItem) {
        copy(item.primaryContent)
        showCopied(item.primaryContent, isBarcode: item.isBarcode)
    }

    /// Also deletes the saved diagnostic capture, which can show the same content.
    func clearHistory() {
        history.clear()
        CaptureService.deleteDiagnostics()
    }

    private func handle(_ result: OCRResult) {
        guard let (item, offersAlternative) = result.clipboardItem(
            mode: Preferences.lineBreakMode, preferBarcode: Preferences.preferBarcode)
        else {
            HUDPanel.shared.show("Không thấy chữ trong vùng này", symbol: "text.magnifyingglass")
            return
        }
        copy(item, offeringAlternative: offersAlternative)
    }

    /// Copies a fresh capture and records it in history. With both text and a barcode, the HUD
    /// offers the other one; taking it updates the history entry, so history copies that instead.
    private func copy(_ item: HistoryItem, offeringAlternative: Bool) {
        if Preferences.saveHistory {
            history.add(item)
        }
        copy(item.primaryContent)
        var alternative: HUDPanel.Action?
        if offeringAlternative {
            var other = item
            other.prefersBarcode.toggle()
            alternative = (other.isBarcode ? "Copy mã QR" : "Copy chữ", { [weak self] in
                self?.copy(other, offeringAlternative: false)
            })
        }
        showCopied(item.primaryContent, isBarcode: item.isBarcode, alternative: alternative)
    }

    /// Shows what landed on the clipboard, so a bad read is noticed before it is pasted.
    private func showCopied(_ content: String, isBarcode: Bool, alternative: HUDPanel.Action? = nil) {
        let lines = content.split(whereSeparator: \.isNewline).count
        let title = isBarcode ? "Đã copy mã QR" : lines > 1 ? "Đã copy \(lines) dòng" : "Đã copy"
        HUDPanel.shared.show(title,
                             detail: TextFormatter.snippet(content, limit: 60),
                             symbol: isBarcode ? "qrcode" : "text.alignleft",
                             action: alternative)
    }
}
