import Foundation

/// A normalized coordinate frame anchored on the patient's midline.
///
/// In this frame the sternal notch is at (0, 0), the midline bottom landmark is at (0, 1),
/// x grows toward the image's right (the patient's left in a frontal photograph), and all
/// distances are expressed as a fraction of the reference length (notch to midline bottom,
/// in pixels). Rotating into this frame removes camera roll from every frontal metric.
public struct MidlineFrame: Equatable, Sendable {
    /// Image-space position of the sternal notch.
    public let origin: Point2D
    /// Pixel distance from sternal notch to midline bottom.
    public let referenceLength: Double
    /// Rotation (radians) applied to image vectors so the midline becomes the +y axis.
    public let rotation: Double

    /// Smallest reference length (pixels) considered non-degenerate.
    public static let minimumReferenceLength: Double = 1.0

    public init?(notch: Point2D, midlineBottom: Point2D) {
        let d = midlineBottom - notch
        let length = d.length
        guard length.isFinite, length >= MidlineFrame.minimumReferenceLength else { return nil }
        origin = notch
        referenceLength = length
        rotation = atan2(d.x, d.y)
    }

    /// Builds a frame from the two midline landmarks, or nil when either is missing or
    /// they coincide.
    public static func from(_ set: LandmarkSet) -> MidlineFrame? {
        guard let notch = set[.sternalNotch], let bottom = set[.midlineBottom] else { return nil }
        return MidlineFrame(notch: notch, midlineBottom: bottom)
    }

    /// Image pixel coordinates to normalized midline coordinates.
    public func normalize(_ p: Point2D) -> Point2D {
        (p - origin).rotated(by: rotation) * (1.0 / referenceLength)
    }

    /// Normalized midline coordinates back to image pixel coordinates.
    public func denormalize(_ p: Point2D) -> Point2D {
        (p * referenceLength).rotated(by: -rotation) + origin
    }

    /// Normalizes every point landmark and contour point of a set.
    public func normalize(_ set: LandmarkSet) -> LandmarkSet {
        var out = set
        out.points = set.points.mapValues(normalize)
        out.leftContour = set.leftContour.map(normalize)
        out.rightContour = set.rightContour.map(normalize)
        return out
    }
}
