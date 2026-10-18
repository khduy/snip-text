import CoreGraphics
import Foundation
import Vision

public struct OCRResult: Sendable {
    public var fragments: [OCRFragment]
    public var barcodes: [String]

    public func text(mode: LineBreakMode) -> String {
        TextFormatter.format(fragments, mode: mode)
    }
}

public enum OCRService {
    /// Runs text recognition and barcode detection on the image in parallel.
    public static func recognize(_ image: CGImage) async throws -> OCRResult {
        async let fragments = recognizeText(image)
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

    static func recognizeText(_ image: CGImage) async throws -> [OCRFragment] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        // Hinting both languages beats automatic detection, which sometimes picks English
        // for short Vietnamese text and drops every diacritic ("Bảo mật" -> "Bao mat").
        let supported = Set(request.supportedRecognitionLanguages.map { $0.maximalIdentifier })
        let wanted = ["vi-VT", "en-US"].map { Locale.Language(identifier: $0) }
        let available = wanted.filter { supported.contains($0.maximalIdentifier) }
        if !available.isEmpty {
            request.recognitionLanguages = available
        }

        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRFragment(text: candidate.string, box: observation.boundingBox.cgRect)
        }
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
