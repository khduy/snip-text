import CoreGraphics
import Testing
@testable import SnipTextKit

/// A 2x image (200×100 pixels for 100×50 points) whose pixel at (x, y), top-left origin,
/// has red = x and green = y, so a crop shows where it came from.
private func gradientImage() -> CGImage {
    let width = 200, height = 100
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            pixels[offset] = UInt8(x)
            pixels[offset + 1] = UInt8(y)
            pixels[offset + 2] = 0
        }
    }
    let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

private func topLeftPixel(_ image: CGImage) -> (red: UInt8, green: UInt8) {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw so that the image's top-left pixel lands on the 1×1 context.
    context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
    return (pixel[0], pixel[1])
}

@Suite struct CaptureServiceTests {
    @Test func flipsViewRectToTopLeftOrigin() {
        let rect = CGRect(x: 10, y: 5, width: 30, height: 20)
        #expect(CaptureService.topLeftRect(rect, inHeight: 50) == CGRect(x: 10, y: 25, width: 30, height: 20))
    }

    @Test func cropsPointsAtDisplayScale() throws {
        let crop = try #require(CaptureService.crop(
            gradientImage(), toPoints: CGRect(x: 10, y: 5, width: 30, height: 20),
            pointSize: CGSize(width: 100, height: 50)))
        #expect(crop.width == 60 && crop.height == 40)
        let pixel = topLeftPixel(crop)
        #expect(pixel.red == 20 && pixel.green == 10)
    }
}
