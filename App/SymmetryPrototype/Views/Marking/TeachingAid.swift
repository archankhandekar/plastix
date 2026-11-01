import SwiftUI
import SymmetryCore

/// The practice-only teaching aid: where the virtual patient's points really are, and a
/// plain check of each placed point against its ring. Pure functions, no UI state.
///
/// The ring radius is 2 sigma L in pixels (sigma from Settings, L the ground-truth notch to
/// midline bottom distance), which is about the size of the ± for one point. There is never
/// a count, a tally or a grade: one whole sentence per point, nothing more.
enum TeachingCheck {
    /// Where a placed point sits relative to its ring.
    enum Placement: Equatable {
        case inside, outside, notPlaced
    }

    static let caption = "The rings show where the virtual patient's points are. Each ring is about the size of the ± for one point. They appear only on practice photos."
    static let showRingsTitle = "Show where the points go"
    static let checkTitle = "Check my points"

    /// 2 * sigma * |notch - midline bottom| in pixels; nil when either truth point is missing.
    static func ringRadiusPixels(truth: LandmarkSet, sigma: Double) -> Double? {
        guard let notch = truth[.sternalNotch], let bottom = truth[.midlineBottom] else { return nil }
        return 2 * sigma * notch.distance(to: bottom)
    }

    /// Inside (on the ring counts as inside), outside, or not placed; nil when the point has
    /// no ground truth on this photo.
    static func placement(of type: LandmarkType, placed: LandmarkSet?, truth: LandmarkSet, radius: Double) -> Placement? {
        guard let target = truth[type] else { return nil }
        guard let p = placed?[type] else { return .notPlaced }
        return p.distance(to: target) <= radius ? .inside : .outside
    }

    /// One whole-literal line per point with ground truth, in `LandmarkType.allCases` order.
    /// Empty when the ring size cannot be worked out (a midline truth point is missing).
    static func lines(placed: LandmarkSet?, truth: LandmarkSet, sigma: Double) -> [String] {
        guard let radius = ringRadiusPixels(truth: truth, sigma: sigma) else { return [] }
        return LandmarkType.allCases.compactMap { type in
            placement(of: type, placed: placed, truth: truth, radius: radius).map { line(type, $0) }
        }
    }

    /// Ground truth in the pixel space of a photo of `size` (the processed capture can differ
    /// in size from the render it came from).
    static func scaled(_ truth: LandmarkSet, to size: Point2D) -> LandmarkSet {
        guard truth.imageSize.x > 0, truth.imageSize.y > 0, size.x > 0, size.y > 0,
              truth.imageSize != size else { return truth }
        let sx = size.x / truth.imageSize.x, sy = size.y / truth.imageSize.y
        func f(_ p: Point2D) -> Point2D { Point2D(x: p.x * sx, y: p.y * sy) }
        return LandmarkSet(points: truth.points.mapValues(f), leftContour: truth.leftContour.map(f),
                           rightContour: truth.rightContour.map(f), imageSize: size)
    }

    /// Whole literals only, never interpolated, so the copy guard sees every word.
    static func line(_ type: LandmarkType, _ placement: Placement) -> String {
        switch (type, placement) {
        case (.leftNipple, .inside): return "Patient left nipple: inside its ring."
        case (.leftNipple, .outside): return "Patient left nipple: outside its ring. Drag it closer."
        case (.leftNipple, .notPlaced): return "Patient left nipple: not placed yet."
        case (.rightNipple, .inside): return "Patient right nipple: inside its ring."
        case (.rightNipple, .outside): return "Patient right nipple: outside its ring. Drag it closer."
        case (.rightNipple, .notPlaced): return "Patient right nipple: not placed yet."
        case (.leftIMF, .inside): return "Patient left fold: inside its ring."
        case (.leftIMF, .outside): return "Patient left fold: outside its ring. Drag it closer."
        case (.leftIMF, .notPlaced): return "Patient left fold: not placed yet."
        case (.rightIMF, .inside): return "Patient right fold: inside its ring."
        case (.rightIMF, .outside): return "Patient right fold: outside its ring. Drag it closer."
        case (.rightIMF, .notPlaced): return "Patient right fold: not placed yet."
        case (.sternalNotch, .inside): return "Sternal notch: inside its ring."
        case (.sternalNotch, .outside): return "Sternal notch: outside its ring. Drag it closer."
        case (.sternalNotch, .notPlaced): return "Sternal notch: not placed yet."
        case (.midlineBottom, .inside): return "Midline bottom: inside its ring."
        case (.midlineBottom, .outside): return "Midline bottom: outside its ring. Drag it closer."
        case (.midlineBottom, .notPlaced): return "Midline bottom: not placed yet."
        }
    }
}

/// Hollow dashed violet circles at the virtual patient's ground-truth points, mapped from
/// pixels through the canvas fit rect. Drawn only on practice photos.
struct TeachingRings: View {
    let truth: LandmarkSet
    let radiusPixels: Double
    /// The pixel size the truth coordinates refer to.
    let pixelSize: CGSize
    /// Where the photo sits in the canvas.
    let fit: CGRect

    var body: some View {
        Canvas { ctx, _ in
            guard pixelSize.width > 0, pixelSize.height > 0 else { return }
            let sx = fit.width / pixelSize.width, sy = fit.height / pixelSize.height
            let r = max(4, CGFloat(radiusPixels) * sx)
            let dash: [CGFloat] = [5, 4]
            for type in LandmarkType.allCases {
                guard let p = truth[type] else { continue }
                let c = CGPoint(x: fit.minX + CGFloat(p.x) * sx, y: fit.minY + CGFloat(p.y) * sy)
                let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                // A dashed Plate halo under the dashes keeps the ring hollow and readable on skin.
                ctx.stroke(ring, with: .color(Theme.Colors.plate.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .butt, dash: dash))
                ctx.stroke(ring, with: .color(Theme.Colors.markerOnPlate),
                           style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: dash))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
