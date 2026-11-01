import CoreGraphics
import SymmetryCore

/// Plate coordinates for one frontal photo. Pure geometry, no drawing.
///
/// The plate is square. The patient midline runs straight down the centre (`axisX`), the
/// sternal notch sits at `notchY` (18 percent of the height) and one reference length L
/// spans `pointsPerL` (height / 1.6), so the midline bottom lands at `bottomY`.
///
/// A normalized point n = frame.normalize(p) maps to (axisX + n.x * k, notchY + n.y * k).
/// The photo is drawn with `imageTransform`: translate(-origin), then rotate(+rotation),
/// then scale(k / L), then offset to (axisX, notchY). That matches `MidlineFrame.normalize`
/// exactly, because CGAffineTransform rotation and `Point2D.rotated` use the same matrix.
struct PlateGeometry {
    static let notchFraction: CGFloat = 0.18
    static let spanL: CGFloat = 1.6

    let frame: MidlineFrame
    let size: CGSize

    init(frame: MidlineFrame, size: CGSize) {
        self.frame = frame
        self.size = size
    }

    /// Nil when the notch or midline bottom is missing, or they coincide.
    init?(landmarks: LandmarkSet, size: CGSize) {
        guard let frame = MidlineFrame.from(landmarks) else { return nil }
        self.init(frame: frame, size: size)
    }

    /// Plate points per reference length L.
    var pointsPerL: CGFloat { size.height / Self.spanL }
    var axisX: CGFloat { size.width / 2 }
    var notchY: CGFloat { size.height * Self.notchFraction }
    var bottomY: CGFloat { notchY + pointsPerL }

    /// A point in normalized midline coordinates (x toward patient left, y down, in L).
    func viewPoint(normalized p: Point2D) -> CGPoint {
        CGPoint(x: axisX + CGFloat(p.x) * pointsPerL,
                y: notchY + CGFloat(p.y) * pointsPerL)
    }

    /// A point in image pixel coordinates.
    func viewPoint(pixel p: Point2D) -> CGPoint {
        viewPoint(normalized: frame.normalize(p))
    }

    /// A patient-right pixel point mirrored across the midline onto the patient-left side,
    /// the same as `Point2D.mirroredX(about: 0)` in normalized coordinates.
    func mirroredViewPoint(pixel p: Point2D) -> CGPoint {
        viewPoint(normalized: frame.normalize(p).mirroredX(about: 0))
    }

    /// A ± in L, as plate points.
    func uncertaintyPoints(_ u: Double) -> CGFloat {
        CGFloat(abs(u)) * pointsPerL
    }

    /// Image pixels to plate points, with the midline vertical.
    var imageTransform: CGAffineTransform { turnTransform(progress: 1) }

    /// The image transform part way through the plumb turn: progress 0 keeps the captured
    /// angle, 1 has the midline running straight down. Scale and position are the same throughout.
    func turnTransform(progress: Double) -> CGAffineTransform {
        let k = pointsPerL
        let l = CGFloat(frame.referenceLength)
        return CGAffineTransform(translationX: axisX, y: notchY)
            .scaledBy(x: k / l, y: k / l)
            .rotated(by: CGFloat(frame.rotation * progress))
            .translatedBy(x: -CGFloat(frame.origin.x), y: -CGFloat(frame.origin.y))
    }

    /// True when the landmarks hold a usable notch and midline bottom.
    static func canTurn(_ landmarks: LandmarkSet?) -> Bool {
        guard let landmarks else { return false }
        return MidlineFrame.from(landmarks) != nil
    }
}
