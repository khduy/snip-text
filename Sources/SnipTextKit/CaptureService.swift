import CoreGraphics
import Foundation
import ImageIO
import os
import ScreenCaptureKit
import UniformTypeIdentifiers

/// A frozen image of one display, at full pixel resolution.
public struct DisplaySnapshot: @unchecked Sendable {
    public var displayID: CGDirectDisplayID
    public var image: CGImage
}

public enum CaptureError: Error {
    /// The display the region was picked on went away before it could be captured.
    case displayUnavailable
}

public enum CaptureService {
    /// When diagnostics are on, the most recent capture is kept here to help diagnose OCR results.
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

    /// Captures one region, given in points with origin top-left within a display, as it looks now.
    /// Used when the screen is not frozen; SnipText's own windows (the overlay) are left out.
    public static func captureRegion(onDisplay displayID: CGDirectDisplayID, rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayUnavailable
        }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }

        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.sourceRect = rect
        configuration.width = Int(rect.width * scale)
        configuration.height = Int(rect.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// Crops a region given in points (origin top-left) out of a snapshot.
    public static func crop(_ image: CGImage, toPoints rect: CGRect, pointSize: CGSize) -> CGImage? {
        let scale = CGFloat(image.width) / pointSize.width
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale).integral
        return image.cropping(to: pixels)
    }

    /// Bumped by every delete. A save started before a delete must not write its image after it.
    private static let diagnosticsGeneration = OSAllocatedUnfairLock(initialState: 0)

    /// Writes the image in the background. Whether it may be written is settled now, on the
    /// caller's side: if `deleteDiagnostics()` runs before the write finishes, the image is dropped.
    @discardableResult
    public static func saveForDiagnostics(_ image: CGImage) -> Task<Void, Never> {
        let generation = diagnosticsGeneration.withLock { $0 }
        return Task.detached(priority: .background) {
            write(image, ifStill: generation)
        }
    }

    public static func deleteDiagnostics() {
        diagnosticsGeneration.withLock { generation in
            generation += 1
            try? FileManager.default.removeItem(at: lastCaptureURL)
        }
    }

    /// Encodes in memory, so nothing touches the disk until the write, which happens under
    /// the lock: a delete can never land between the check and the write. Not `.atomic`, which
    /// goes through a temporary file that a crash would leave behind; a half-written image stays
    /// at `lastCaptureURL`, where the next delete removes it.
    private static func write(_ image: CGImage, ifStill generation: Int) {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return }

        let png = data as Data
        let url = lastCaptureURL
        diagnosticsGeneration.withLock { current in
            guard current == generation else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: url)
        }
    }
}
