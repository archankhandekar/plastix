import CoreGraphics
import CoreImage

/// Bitmap helpers and the blurred variant. Nothing is burned into the renders: a baked
/// label would read mirror-reversed on the app's flipped right oblique and as a smudge on
/// the blurred frontal, so the app's own practice band and photo tags are the only marker.
enum PostProcess {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An sRGB RGBA context the size of the image.
    static func context(width: Int, height: Int) -> CGContext {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fail("Cannot create a bitmap context")
        }
        return ctx
    }

    /// CIGaussianBlur with radius 8 on the clean render, cropped back to the original
    /// extent. The software renderer keeps the output deterministic.
    static func blurred(_ image: CGImage) -> CGImage {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { fail("CIGaussianBlur is unavailable") }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(8.0, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { fail("Blur produced no image") }
        let ci = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB, .useSoftwareRenderer: true])
        guard let cg = ci.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: sRGB) else {
            fail("Cannot render the blurred image")
        }
        return cg
    }
}
