import AppKit
import SnipTextKit
import SwiftUI

/// Debug entry points, used to check the app without a person at the keyboard.
///
/// `open SnipText.app --args --self-test` captures the main display with the app's own
/// Screen Recording permission, OCRs the menu bar strip, writes a report and quits.
///
/// `open SnipText.app --args --render-previews <dir>` renders the selection overlay, the HUD,
/// the menu bar icon and the onboarding steps (with synthetic content, no screen access needed)
/// to PNGs and quits.
@MainActor
enum SelfTest {
    static let reportURL = CaptureService.lastCaptureURL
        .deletingLastPathComponent()
        .appendingPathComponent("self-test.txt")

    static var isRequested: Bool {
        CommandLine.arguments.contains("--self-test") || isFocusTest || previewDirectory != nil
    }

    /// `open -g SnipText.app --args --focus-test`: shows the overlay over the current app for a
    /// second, cancels it, and reports whether focus went back to that app.
    private static var isFocusTest: Bool {
        CommandLine.arguments.contains("--focus-test")
    }

    private static var previewDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-previews"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func run() {
        if isFocusTest {
            runFocusTest()
            return
        }
        if let directory = previewDirectory {
            renderPreviews(to: directory)
            NSApp.terminate(nil)
            return
        }

        Task {
            let hasAccess = Permissions.hasScreenCaptureAccess
            var report = ["screen access: \(hasAccess)"]
            if !hasAccess {
                // Registers the app in System Settings so the user only has to flip the switch.
                Permissions.hasPromptedForAccess = true
                CGRequestScreenCaptureAccess()
            }
            do {
                let snapshots = try await CaptureService.captureDisplays()
                let mainID = NSScreen.main?.displayID
                if let snapshot = snapshots.first(where: { $0.displayID == mainID }) ?? snapshots.first,
                   let screen = NSScreen.screens.first(where: { $0.displayID == snapshot.displayID }),
                   let strip = CaptureService.crop(
                       snapshot.image, toPoints: CGRect(x: 0, y: 0, width: screen.frame.width, height: 40),
                       pointSize: screen.frame.size) {
                    await CaptureService.saveForDiagnostics(strip).value
                    let result = try await OCRService.recognize(strip)
                    report.append("displays: \(snapshots.count), snapshot: \(snapshot.image.width)x\(snapshot.image.height)")
                    report.append("strip: \(strip.width)x\(strip.height)")
                    report.append("fragments: \(result.fragments.count), barcodes: \(result.barcodes.count)")
                    report.append("text:\n\(result.text(mode: .keepLines))")
                } else {
                    report.append("capture produced no image")
                }
            } catch {
                report.append("error: \(error)")
            }
            writeReport(report)
            NSApp.terminate(nil)
        }
    }

    private static func runFocusTest() {
        Task {
            let before = NSWorkspace.shared.frontmostApplication
            var report = ["before: \(before?.localizedName ?? "nil")"]
            do {
                let snapshots = try await CaptureService.captureDisplays()
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    report.append("during: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")
                    SelectionOverlay.cancelActive()
                }
                _ = try await SelectionOverlay.selectRegion(from: snapshots)
                try? await Task.sleep(for: .milliseconds(500))
                let after = NSWorkspace.shared.frontmostApplication
                report.append("after: \(after?.localizedName ?? "nil")")
                report.append(after == before ? "PASS: focus restored" : "FAIL: focus not restored")
            } catch {
                report.append("error: \(error)")
            }
            writeReport(report)
            NSApp.terminate(nil)
        }
    }

    private static func writeReport(_ lines: [String]) {
        try? FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
    }

    // MARK: Previews

    private static func renderPreviews(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = CGSize(width: 1440, height: 900)

        let overlay = SelectionView(image: syntheticScreen(size: size, scale: 2))
        let shots: [(String, NSRect?)] = [
            ("overlay-idle", nil),
            ("overlay-selecting", NSRect(x: 180, y: 520, width: 620, height: 170)),
        ]
        for (name, selection) in shots {
            if let rep = overlay.renderPreview(size: size, selection: selection) {
                write(rep, to: directory.appendingPathComponent("\(name).png"))
            }
        }

        let toasts: [(String, HUDView)] = [
            ("hud-text", HUDView(title: "Đã copy 3 dòng", detail: "Hoá đơn số 00123 – Công ty TNHH Thương mại Dịch vụ POS…",
                                 symbol: "text.alignleft", action: nil)),
            ("hud-both", HUDView(title: "Đã copy", detail: "Quét mã để thanh toán", symbol: "text.alignleft",
                                 action: ("Copy mã QR", {}))),
            ("hud-empty", HUDView(title: "Không thấy chữ trong vùng này", detail: nil,
                                  symbol: "text.magnifyingglass", action: nil)),
        ]
        for (name, view) in toasts {
            let renderer = ImageRenderer(content: view.padding(20).background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            if let image = renderer.cgImage {
                write(NSBitmapImageRep(cgImage: image), to: directory.appendingPathComponent("\(name).png"))
            }
        }

        for needsAttention in [false, true] {
            let icon = MenuBarIcon.image(needsAttention: needsAttention)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36 * 4, pixelsHigh: 36 * 4,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: 36, height: 36)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 36, height: 36).fill()
            icon.draw(in: NSRect(x: 9, y: 9, width: 18, height: 18))
            NSGraphicsContext.restoreGraphicsState()
            write(rep, to: directory.appendingPathComponent("menubar-icon\(needsAttention ? "-attention" : "").png"))
        }

        for step in OnboardingModel.Step.allCases {
            let renderer = ImageRenderer(content: OnboardingView(model: OnboardingModel(step: step))
                .background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            if let image = renderer.cgImage {
                write(NSBitmapImageRep(cgImage: image), to: directory.appendingPathComponent("onboarding-\(step).png"))
            }
        }
    }

    /// A fake desktop: a light window with a few paragraphs of text.
    private static func syntheticScreen(size: CGSize, scale: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(red: 0.30, green: 0.45, blue: 0.65, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(.white)
        context.fill(CGRect(x: 120, y: 120, width: 1000, height: 660))

        let lines = [
            ("SnipText – lấy chữ từ màn hình", 28.0),
            ("Kéo chọn một vùng bất kỳ, chữ sẽ được copy vào clipboard.", 18.0),
            ("Hỗ trợ tiếng Việt có dấu và English, chạy hoàn toàn offline.", 18.0),
            ("The quick brown fox jumps over the lazy dog 0123456789.", 15.0),
        ]
        var y = 700.0
        for (text, fontSize) in lines {
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.black,
            ])
            context.textPosition = CGPoint(x: 160, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            y -= fontSize * 2.4
        }
        return context.makeImage()!
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) {
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
