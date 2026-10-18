import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// A frozen image of one display, at full pixel resolution.
public struct DisplaySnapshot: @unchecked Sendable {
    public var displayID: CGDirectDisplayID
    public var image: CGImage
}

public enum CaptureService {
    /// The most recent capture is kept here to help diagnose OCR results.
    public static let lastCaptureURL = URL.cachesDirectory
        .appendingPathComponent("SnipText", isDirectory: true)
        .appendingPathComponent("last-capture.png")

    /// Captures every display, leaving out SnipText's own windows (menu, HUD).
    public static func captureDisplays() async throws -> [DisplaySnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }

        var snapshots: [DisplaySnapshot] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int(filter.contentRect.width * scale)
            configuration.height = Int(filter.contentRect.height * scale)
            configuration.showsCursor = false
            configuration.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            snapshots.append(DisplaySnapshot(displayID: display.displayID, image: image))
        }
        return snapshots
    }

    /// Crops a region given in points (origin top-left) out of a snapshot.
    public static func crop(_ image: CGImage, toPoints rect: CGRect, pointSize: CGSize) -> CGImage? {
        let scale = CGFloat(image.width) / pointSize.width
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale).integral
        return image.cropping(to: pixels)
    }

    public static func saveForDiagnostics(_ image: CGImage) {
        let url = lastCaptureURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
