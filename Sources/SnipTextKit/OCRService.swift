import CoreGraphics
import Foundation
import Vision

public struct OCRResult: Sendable {
    public var fragments: [OCRFragment]
    public var barcodes: [String]

    public init(fragments: [OCRFragment], barcodes: [String]) {
        self.fragments = fragments
        self.barcodes = barcodes
    }

    public func text(mode: LineBreakMode) -> String {
        TextFormatter.format(fragments, mode: mode)
    }

    /// What a capture puts on the clipboard, or nil when nothing was found. With both text and
    /// a barcode, `preferBarcode` picks one and the other is worth offering as an alternative.
    public func clipboardItem(mode: LineBreakMode, preferBarcode: Bool)
        -> (item: HistoryItem, offersAlternative: Bool)? {
        let text = text(mode: mode)
        switch (text.isEmpty, barcodes.isEmpty) {
        case (true, true):
            return nil
        case (true, false), (false, true):
            return (HistoryItem(text: text, barcodes: barcodes), false)
        case (false, false):
            return (HistoryItem(text: text, barcodes: barcodes, prefersBarcode: preferBarcode), true)
        }
    }
}

public enum OCRService {
    /// Runs text recognition and barcode detection on the image in parallel.
    /// `correctsLanguage` off keeps code as written: correction turns `main()` into `main ()`.
    public static func recognize(_ image: CGImage, correctsLanguage: Bool = true) async throws -> OCRResult {
        async let fragments = recognizeText(image, correctsLanguage: correctsLanguage)
        async let barcodes = detectBarcodes(image)
        return try await OCRResult(fragments: fragments, barcodes: barcodes)
    }

    /// Loads the recognition models ahead of time so the first real capture is fast.
    public static func warmUp() async {
        let context = CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        guard let image = context?.makeImage() else { return }
        _ = try? await recognize(image)
    }

    /// Lines shorter than this, in pixels, are read again from an enlarged copy: 10–11 pt text
    /// on a 1x display comes out as noise at its own size and reads cleanly at 2–3x.
    static let smallTextHeight: CGFloat = 20

    static func recognizeText(_ image: CGImage, correctsLanguage: Bool = true) async throws -> [OCRFragment] {
        let fragments = try await recognizeTextOnce(image, correctsLanguage: correctsLanguage)
        let heights = fragments.map { $0.box.height * CGFloat(image.height) }.sorted()
        guard !heights.isEmpty else { return fragments }
        let median = heights[heights.count / 2]
        guard median < smallTextHeight,
              let larger = upscale(image, by: min(3, Int((32 / median).rounded(.up))))
        else { return fragments }
        // Boxes are normalized, so they mean the same on the larger image.
        return try await recognizeTextOnce(larger, correctsLanguage: correctsLanguage)
    }

    private static func recognizeTextOnce(_ image: CGImage, correctsLanguage: Bool) async throws -> [OCRFragment] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = correctsLanguage
        // Vision picks the language per image, among every one it supports.
        request.automaticallyDetectsLanguage = true

        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRFragment(text: candidate.string, box: observation.boundingBox.cgRect)
        }
    }

    /// Nil when the result would be too large to be worth it.
    static func upscale(_ image: CGImage, by factor: Int) -> CGImage? {
        let width = image.width * factor, height = image.height * factor
        guard factor > 1, max(width, height) <= 8192,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func detectBarcodes(_ image: CGImage) async throws -> [String] {
        let request = DetectBarcodesRequest()
        let observations = try await request.perform(on: image)
        var seen = Set<String>()
        return observations
            .compactMap(\.payloadString)
            .filter { seen.insert($0).inserted }
    }
}
