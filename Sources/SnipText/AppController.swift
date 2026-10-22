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
        Task.detached(priority: .utility) { await OCRService.warmUp() }

        if SelfTest.isRequested {
            SelfTest.run()
        } else {
            OnboardingWindow.onTryNow = { [weak self] in self?.capture() }
            OnboardingWindow.showIfNeeded()
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
                CaptureService.saveForDiagnostics(image)
                let result = try await OCRService.recognize(image)
                logger.notice("""
                    captured \(image.width)x\(image.height), \
                    \(result.fragments.count) text fragments, \(result.barcodes.count) barcodes
                    """)
                handle(result)
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
        showCopied(item.primaryContent, isBarcode: item.text.isEmpty)
    }

    private func handle(_ result: OCRResult) {
        let text = result.text(mode: Preferences.lineBreakMode)
        let barcodes = result.barcodes.joined(separator: "\n")

        switch (text.isEmpty, barcodes.isEmpty) {
        case (true, true):
            HUDPanel.shared.show("Không thấy chữ trong vùng này", symbol: "text.magnifyingglass")
            return
        case (true, false):
            copy(barcodes)
            showCopied(barcodes, isBarcode: true)
        case (false, true):
            copy(text)
            showCopied(text, isBarcode: false)
        case (false, false) where Preferences.preferBarcode:
            copy(barcodes)
            showCopied(barcodes, isBarcode: true, alternative: ("Copy chữ", { [weak self] in
                self?.copy(text)
                self?.showCopied(text, isBarcode: false)
            }))
        case (false, false):
            copy(text)
            showCopied(text, isBarcode: false, alternative: ("Copy mã QR", { [weak self] in
                self?.copy(barcodes)
                self?.showCopied(barcodes, isBarcode: true)
            }))
        }

        history.add(HistoryItem(text: text, barcodes: result.barcodes))
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
