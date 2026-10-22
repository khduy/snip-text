import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Testing
@testable import SnipTextKit

/// Renders black text lines on a white canvas, like a screenshot would look.
private func renderText(_ lines: [String], font: NSFont = .systemFont(ofSize: 32)) -> CGImage {
    let fontSize = font.pointSize
    let width = 1200, lineHeight = Int(fontSize * 1.6)
    let height = lineHeight * lines.count + 40
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(.white)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black,
    ]
    for (index, text) in lines.enumerated() {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: 20, y: CGFloat(height - 20 - (index + 1) * lineHeight) + fontSize * 0.4)
        CTLineDraw(line, context)
    }
    return context.makeImage()!
}

private func renderQRCode(_ payload: String) -> CGImage {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(payload.utf8)
    let output = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    let padded = output.composited(over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -40, dy: -40)))
    return CIContext().createCGImage(padded, from: padded.extent)!
}

@Suite struct OCRServiceTests {
    @Test func recognizesVietnameseAndEnglish() async throws {
        let image = renderText(["Xin chào thế giới", "Hello OCR 2026"])
        let result = try await OCRService.recognize(image)
        let text = result.text(mode: .keepLines)

        #expect(text.contains("Xin chào thế giới"), "got: \(text)")
        #expect(text.contains("Hello OCR 2026"), "got: \(text)")
        #expect(result.barcodes.isEmpty)
    }

    @Test func recognizesVietnameseOnly() async throws {
        let lines = ["Tiếng Việt có dấu đầy đủ", "Người dùng nhận được thông báo"]
        let text = try await OCRService.recognize(renderText(lines)).text(mode: .keepLines)

        for line in lines {
            #expect(text.contains(line), "got: \(text)")
        }
    }

    @Test func recognizesEnglishOnly() async throws {
        let lines = ["The quick brown fox jumps over the lazy dog", "Settings and permissions"]
        let text = try await OCRService.recognize(renderText(lines)).text(mode: .keepLines)

        for line in lines {
            #expect(text.contains(line), "got: \(text)")
        }
    }

    @Test func keepsCodeIndentation() async throws {
        // No brace-only lines: Vision often skips a line holding a lone "}".
        let code = [
            "def main():",
            "    total = 42",
            "    if total > 0:",
            "        print(total)",
            "    return total",
        ]
        let image = renderText(code, font: .monospacedSystemFont(ofSize: 24, weight: .regular))
        let text = try await OCRService.recognize(image, correctsLanguage: false).text(mode: .preserveIndent)
        let indents: [Int] = text.components(separatedBy: "\n").map { line in line.prefix { $0 == " " }.count }
        #expect(indents == [0, 4, 4, 8, 4], "got:\n\(text)")
    }

    @Test func readsSmallTextByEnlargingIt() async throws {
        // At its own size Vision reads the second line as "Nono conc: 1.250J000 di".
        let lines = ["Hoá đơn số 00123 ngày 21/10", "Tổng cộng: 1.250.000 đ", "Cảm ơn quý khách"]
        let text = try await OCRService.recognize(renderText(lines, font: .systemFont(ofSize: 10)))
            .text(mode: .keepLines)
        #expect(text == lines.joined(separator: "\n"))
    }

    @Test func detectsQRCodePayload() async throws {
        let result = try await OCRService.recognize(renderQRCode("https://example.com/snip"))
        #expect(result.barcodes == ["https://example.com/snip"])
    }
}

@Suite struct ClipboardItemTests {
    private let text = [OCRFragment(text: "chữ", box: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.2))]

    @Test func nothingFoundGivesNil() {
        #expect(OCRResult(fragments: [], barcodes: []).clipboardItem(mode: .keepLines, preferBarcode: false) == nil)
    }

    @Test func singleKindHasNoAlternative() throws {
        let onlyText = try #require(OCRResult(fragments: text, barcodes: [])
            .clipboardItem(mode: .keepLines, preferBarcode: true))
        #expect(onlyText.item.primaryContent == "chữ" && !onlyText.offersAlternative)

        let onlyCode = try #require(OCRResult(fragments: [], barcodes: ["QR"])
            .clipboardItem(mode: .keepLines, preferBarcode: false))
        #expect(onlyCode.item.primaryContent == "QR" && !onlyCode.offersAlternative)
    }

    @Test func bothKindsFollowPreferenceAndOfferTheOther() throws {
        let result = OCRResult(fragments: text, barcodes: ["QR"])
        let textFirst = try #require(result.clipboardItem(mode: .keepLines, preferBarcode: false))
        #expect(textFirst.item.primaryContent == "chữ" && textFirst.offersAlternative)
        let codeFirst = try #require(result.clipboardItem(mode: .keepLines, preferBarcode: true))
        #expect(codeFirst.item.primaryContent == "QR" && codeFirst.offersAlternative)
    }
}
