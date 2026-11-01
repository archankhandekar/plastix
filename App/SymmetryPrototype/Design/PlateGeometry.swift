import CoreGraphics
import SymmetryCore

/// Plate coordinates for one frontal photo. Pure geometry, no drawing.
///
/// The patient midline runs straight down the centre (`axisX`), the sternal notch sits at
/// `notchY` (`framing.notchFraction` of the height) and one reference length L spans
/// `pointsPerL` (height / `framing.spanL`), so the midline bottom lands at `bottomY`.
///
/// Two framings: `.square` (thumbnails and the gallery) and `.wide`, the slightly wider
/// symmetry plate. Both put the notch near the top, clear of the corner tags, and land the
/// midline bottom near the foot of the plate so the torso fills it.
///
/// A normalized point n = frame.normalize(p) maps to (axisX + n.x * k, notchY + n.y * k).
/// The photo is drawn with `imageTransform`: translate(-origin), then rotate(+rotation),
/// then scale(k / L), then offset to (axisX, notchY). That matches `MidlineFrame.normalize`
/// exactly, because CGAffineTransform rotation and `Point2D.rotated` use the same matrix.
struct PlateGeometry {
    /// Where the notch sits and how many L the plate's height spans, for one plate shape.
    struct Framing: Equatable {
        /// The notch's distance from the top, as a share of the height.
        let notchFraction: CGFloat
        /// The plate's height in reference lengths L.
        let spanL: CGFloat
        /// Width over height.
        let aspectRatio: CGFloat

        /// Square: the notch at 10 percent, the midline bottom at about 81 percent.
        static let square = Framing(notchFraction: 0.10, spanL: 1.4, aspectRatio: 1)
        /// The symmetry plate, 8 wide by 7 high: the notch at 10 percent and the midline
        /// bottom at about 88 percent, so the breasts are drawn larger and both gutters
        /// beside the torso are wide enough for a readout.
        static let wide = Framing(notchFraction: 0.10, spanL: 1.28, aspectRatio: 8.0 / 7.0)
    }

    let frame: MidlineFrame
    let size: CGSize
    let framing: Framing

    init(frame: MidlineFrame, size: CGSize, framing: Framing = .square) {
        self.frame = frame
        self.size = size
        self.framing = framing
    }

    /// Nil when the notch or midline bottom is missing, or they coincide.
    init?(landmarks: LandmarkSet, size: CGSize, framing: Framing = .square) {
        guard let frame = MidlineFrame.from(landmarks) else { return nil }
        self.init(frame: frame, size: size, framing: framing)
    }

    /// Plate points per reference length L.
    var pointsPerL: CGFloat { size.height / framing.spanL }
    var axisX: CGFloat { size.width / 2 }
    var notchY: CGFloat { size.height * framing.notchFraction }
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
