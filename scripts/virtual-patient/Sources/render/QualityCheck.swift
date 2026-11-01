import CoreGraphics
import Foundation
import ImageIO
import SymmetryCore
import UniformTypeIdentifiers

/// Runs the app's own quality gate on each encoded JPEG, so a render that the app would
/// call blurred or clipped never ships.
enum QualityCheck {
    /// Stricter than the app's defaults (60 and 0.05), so the bundled renders pass with
    /// margin.
    static let minSharpBlur = 90.0
    static let maxClipped = 0.02
    static let maxBlurredBlur = 60.0

    struct Result {
        let blurScore: Double
        let highlight: Double
        let shadow: Double
    }

    /// Exactly ImageBridge.luminance in the app: a DeviceGray context, the same rounding
    /// of w and h, and interpolation quality .medium.
    static func luminance(from cg: CGImage, maxSide: Int) -> LuminanceImage? {
        let scale = min(1, Double(maxSide) / Double(max(cg.width, cg.height)))
        let w = max(1, Int(Double(cg.width) * scale)), h = max(1, Int(Double(cg.height) * scale))
        var pixels = [UInt8](repeating: 0, count: w * h)
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? LuminanceImage(width: w, height: h, pixels: pixels) : nil
    }

    static func measure(jpeg: Data) -> Result {
        let cg = decode(jpeg)
        guard let lum = luminance(from: cg, maxSide: 256) else { fail("Cannot build the luminance image") }
        let blur = QualityGate.laplacianVariance(lum)
        let (hi, lo) = QualityGate.clippedFractions(lum)
        return Result(blurScore: blur, highlight: hi, shadow: lo)
    }

    /// Returns a failure description, or nil when the render passes.
    static func problem(_ r: Result, blurred: Bool, name: String) -> String? {
        if blurred {
            return r.blurScore >= maxBlurredBlur ? "\(name): blurred render has blur \(r.blurScore), needs < \(maxBlurredBlur)" : nil
        }
        if r.blurScore < minSharpBlur { return "\(name): blur \(r.blurScore) < \(minSharpBlur)" }
        if r.highlight > maxClipped { return "\(name): highlight clipped fraction \(r.highlight) > \(maxClipped)" }
        if r.shadow > maxClipped { return "\(name): shadow clipped fraction \(r.shadow) > \(maxClipped)" }
        return nil
    }

    // MARK: - Image IO

    static func encodeJPEG(_ image: CGImage, quality: Double = 0.8) -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            fail("Cannot create a JPEG destination")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { fail("JPEG encoding failed") }
        return data as Data
    }

    static func encodePNG(_ image: CGImage) -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            fail("Cannot create a PNG destination")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fail("PNG encoding failed") }
        return data as Data
    }

    static func decode(_ data: Data) -> CGImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("Cannot decode an encoded image") }
        return cg
    }
}
