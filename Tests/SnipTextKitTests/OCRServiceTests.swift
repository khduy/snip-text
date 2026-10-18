import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Testing
@testable import SnipTextKit

/// Renders black text lines on a white canvas, like a screenshot would look.
private func renderText(_ lines: [String], fontSize: CGFloat = 32) -> CGImage {
    let width = 1200, lineHeight = Int(fontSize * 1.6)
    let height = lineHeight * lines.count + 40
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(.white)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize),
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

    @Test func detectsQRCodePayload() async throws {
        let result = try await OCRService.recognize(renderQRCode("https://example.com/snip"))
        #expect(result.barcodes == ["https://example.com/snip"])
    }
}
