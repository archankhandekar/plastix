import AppKit
import CoreGraphics
import CoreImage
import CoreText

/// Burns 'Virtual patient' into every rendered pixel set, and makes the blurred variant.
enum Watermark {
    static let text = "Virtual patient"
    static let fontSize: CGFloat = 48
    static let inset: CGFloat = 32
    static let paddingX: CGFloat = 20
    static let paddingY: CGFloat = 12
    static let cornerRadius: CGFloat = 12

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An sRGB RGBA context the size of the image.
    static func context(width: Int, height: Int) -> CGContext {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fail("Cannot create a bitmap context")
        }
        return ctx
    }

    /// The image with the label in the lower-left corner: system semibold 48 px, white
    /// at 90 percent on an rgba(12, 16, 19, 0.75) rounded backing, 32 px from the left
    /// and bottom edges.
    static func burn(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        let ctx = context(width: w, height: h)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold) as CTFont
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        // CoreGraphics puts y = 0 at the bottom row of the image.
        let backing = CGRect(x: inset, y: inset, width: (width + 2 * paddingX).rounded(.up),
                             height: (ascent + descent + 2 * paddingY).rounded(.up))
        ctx.setFillColor(CGColor(srgbRed: 12 / 255, green: 16 / 255, blue: 19 / 255, alpha: 0.75))
        ctx.addPath(CGPath(roundedRect: backing, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        ctx.fillPath()

        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.setShouldAntialias(true)
        ctx.textPosition = CGPoint(x: inset + paddingX, y: inset + paddingY + descent)
        CTLineDraw(line, ctx)
        guard let out = ctx.makeImage() else { fail("Cannot burn the watermark") }
        return out
    }

    /// CIGaussianBlur with radius 8, on the already-watermarked image, cropped back to the
    /// original extent. The software renderer keeps the output deterministic.
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
