import CoreGraphics
import Foundation
import SymmetryCore
import UIKit

/// Bridges platform images to `SymmetryCore` values. All heavy work happens off the main
/// thread via `process`.
enum ImageBridge {
    struct Processed {
        let jpeg: Data
        let width: Int
        let height: Int
        let quality: QualityReport
    }

    /// Decodes captured data, bakes the EXIF orientation into the pixels, re-encodes as
    /// JPEG, and runs the quality gate on a downsampled luminance copy.
    static func process(_ data: Data, tiltDegrees: Double?, thresholds: QualityThresholds) -> Processed? {
        guard let raw = UIImage(data: data) else { return nil }
        let upright = normalizedUp(raw)
        guard let cg = upright.cgImage, let jpeg = upright.jpegData(compressionQuality: 0.92),
              let lum = luminance(from: cg, maxSide: 256) else { return nil }
        let report = QualityGate.evaluate(lum, tiltDegrees: tiltDegrees, thresholds: thresholds)
        return Processed(jpeg: jpeg, width: cg.width, height: cg.height, quality: report)
    }

    /// Redraws the image so its orientation is `.up` and pixel coordinates match what is
    /// displayed. Landmarks are stored in these upright pixel coordinates.
    static func normalizedUp(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.scale == 1 { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Greyscale downsample for quality checks.
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

    /// Renders landmarks and contours onto a copy of the image for export.
    static func annotated(_ image: UIImage, landmarks: LandmarkSet) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            image.draw(at: .zero)
            let c = ctx.cgContext
            let r = max(6, image.size.width / 150)
            c.setLineWidth(max(2, r / 3))
            for contour in [landmarks.leftContour, landmarks.rightContour] where contour.count > 1 {
                c.setStrokeColor(UIColor.systemTeal.cgColor)
                c.move(to: CGPoint(x: contour[0].x, y: contour[0].y))
                for p in contour.dropFirst() { c.addLine(to: CGPoint(x: p.x, y: p.y)) }
                c.strokePath()
            }
            if let n = landmarks[.sternalNotch], let b = landmarks[.midlineBottom] {
                c.setStrokeColor(UIColor.white.cgColor)
                c.move(to: CGPoint(x: n.x, y: n.y)); c.addLine(to: CGPoint(x: b.x, y: b.y)); c.strokePath()
            }
            for (type, p) in landmarks.points {
                c.setFillColor(type == .leftNipple || type == .leftIMF ? UIColor.systemOrange.cgColor : UIColor.systemYellow.cgColor)
                c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
        }
    }
}
