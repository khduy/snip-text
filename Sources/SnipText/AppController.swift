import AppKit
import KeyboardShortcuts
import Observation
import OSLog
import SnipTextKit

private let logger = Logger(subsystem: "vn.posapp.sniptext", category: "capture")

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
                let snapshots = try await CaptureService.captureDisplays()
                guard let image = await SelectionOverlay.selectRegion(from: snapshots) else { return }
                CaptureService.saveForDiagnostics(image)
                let result = try await OCRService.recognize(image)
                logger.notice("""
                    captured \(image.width)x\(image.height), \
                    \(result.fragments.count) text fragments, \(result.barcodes.count) barcodes
                    """)
                handle(result)
            } catch {
                HUDPanel.shared.show("Lỗi: \(error.localizedDescription)")
            }
        }
    }

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func handle(_ result: OCRResult) {
        let text = result.text(mode: Preferences.lineBreakMode)
        let barcodes = result.barcodes.joined(separator: "\n")

        switch (text.isEmpty, barcodes.isEmpty) {
        case (true, true):
            HUDPanel.shared.show("Không tìm thấy chữ")
            return
        case (true, false):
            copy(barcodes)
            HUDPanel.shared.show("Đã đọc mã: \(barcodes)")
        case (false, true):
            copy(text)
            HUDPanel.shared.show("Đã copy")
        case (false, false) where Preferences.preferBarcode:
            copy(barcodes)
            HUDPanel.shared.show("Đã đọc mã: \(barcodes)",
                                 action: ("Copy chữ", { [weak self] in self?.copy(text) }))
        case (false, false):
            copy(text)
            HUDPanel.shared.show("Đã copy",
                                 action: ("Copy mã QR", { [weak self] in self?.copy(barcodes) }))
        }

        history.add(HistoryItem(text: text, barcodes: result.barcodes))
    }
}
