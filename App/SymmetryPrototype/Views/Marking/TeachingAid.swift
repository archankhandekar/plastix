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

/// The virtual patient's ground-truth points as labelled target marks, mapped from pixels
/// through the canvas fit rect. Drawn only on practice photos, inside the marking canvas's
/// own pass so their labels share one collision check with the placed marks.
///
/// Each target is a solid ring at the true check radius (2 sigma L, the size of the ± for one
/// point) with a light fill, plus four short ticks outside it, so even a ring a few points
/// across reads as a clear target and never breaks into dashes. Truth is quiet Plate ink:
/// violet stays for what a hand placed, and blue for what the app derived.
enum TeachingRings {
    /// One drawn target, in canvas points.
    struct Target {
        let type: LandmarkType
        let center: CGPoint
        /// The ring plus its ticks; labels keep outside this.
        let outerRadius: CGFloat
    }

    /// The smallest ring drawn, so a tiny radius still shows a ring and not a dot.
    static let minimumRingRadius: CGFloat = 4
    private static let tickGap: CGFloat = 3
    private static let tickLength: CGFloat = 6

    /// Where each target sits, without drawing.
    static func targets(truth: LandmarkSet, radiusPixels: Double, pixelSize: CGSize, fit: CGRect) -> [Target] {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return [] }
        let sx = fit.width / pixelSize.width, sy = fit.height / pixelSize.height
        let r = max(minimumRingRadius, CGFloat(radiusPixels) * sx)
        return LandmarkType.allCases.compactMap { type in
            guard let p = truth[type] else { return nil }
            let c = CGPoint(x: fit.minX + CGFloat(p.x) * sx, y: fit.minY + CGFloat(p.y) * sy)
            return Target(type: type, center: c, outerRadius: r + tickGap + tickLength)
        }
    }

    /// Draws the targets and returns them, for label placement.
    @discardableResult
    static func draw(in ctx: GraphicsContext, truth: LandmarkSet, radiusPixels: Double,
                     pixelSize: CGSize, fit: CGRect) -> [Target] {
        let targets = targets(truth: truth, radiusPixels: radiusPixels, pixelSize: pixelSize, fit: fit)
        for target in targets {
            let c = target.center
            let r = target.outerRadius - tickGap - tickLength
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            var ticks = Path()
            for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] as [(CGFloat, CGFloat)] {
                ticks.move(to: CGPoint(x: c.x + dx * (r + tickGap), y: c.y + dy * (r + tickGap)))
                ticks.addLine(to: CGPoint(x: c.x + dx * (r + tickGap + tickLength), y: c.y + dy * (r + tickGap + tickLength)))
            }
            ctx.fill(ring, with: .color(Theme.Colors.plateInk.opacity(0.18)))
            ctx.stroke(ring, with: .color(Theme.Colors.plate.opacity(0.75)), lineWidth: 3.5)
            ctx.stroke(ticks, with: .color(Theme.Colors.plate.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            ctx.stroke(ring, with: .color(Theme.Colors.plateInk), lineWidth: 1.5)
            ctx.stroke(ticks, with: .color(Theme.Colors.plateInk), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        return targets
    }
}
