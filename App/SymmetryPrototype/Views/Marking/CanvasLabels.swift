import SwiftUI
import SymmetryCore

/// Labels on the marking canvas, placed so they never sit on each other or on a mark.
///
/// Canvas labels use a fixed 15pt semibold face (the `.subheadline` floor at the default
/// size) that does not grow with Dynamic Type: the chip map under the photo shows the same
/// names at the reader's text size, and labels that grow would bury the marks.
///
/// Placement is a greedy pass. Each label tries spots pushed away from the midline (patient
/// right to the screen left of its point, patient left to the screen right, the notch above
/// and the midline bottom below), then further out, and takes the first spot that is inside
/// the canvas and clear of every mark and every label already placed. A label pushed away
/// from its point gets a thin leader line. A label with no clear spot is dropped, unless it is
/// the selected point, which is always labelled.
struct CanvasLabelPlacer {
    /// Which way a label is pushed from its point.
    enum Direction {
        case screenLeft, screenRight, above, below

        /// Patient right is on the screen's left of a frontal photo; the notch reads above
        /// its point and the midline bottom below it.
        static func forPoint(_ type: LandmarkType) -> Direction {
            switch type {
            case .rightNipple, .rightIMF: return .screenLeft
            case .leftNipple, .leftIMF: return .screenRight
            case .sternalNotch: return .above
            case .midlineBottom: return .below
            }
        }
    }

    static let font = Font.system(size: 15, weight: .semibold)
    private static let padX: CGFloat = 5
    private static let padY: CGFloat = 2
    private static let pushes: [CGFloat] = [0, 10, 22, 36, 54, 76, 100, 128]

    private let bounds: CGRect
    private var occupied: [CGRect]

    /// `obstacles` are the marks, rings and lines labels must not cover, in canvas points.
    init(bounds: CGRect, obstacles: [CGRect]) {
        self.bounds = bounds
        self.occupied = obstacles
    }

    /// Rects covering a polyline, sampled every few points, as obstacles.
    static func obstacles(along points: [CGPoint], halfWidth: CGFloat) -> [CGRect] {
        guard points.count > 1 else {
            return points.map { CGRect(x: $0.x - halfWidth, y: $0.y - halfWidth, width: 2 * halfWidth, height: 2 * halfWidth) }
        }
        var rects: [CGRect] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / 8))
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                rects.append(CGRect(x: p.x - halfWidth, y: p.y - halfWidth, width: 2 * halfWidth, height: 2 * halfWidth))
            }
        }
        return rects
    }

    /// Places and draws one label for a point at `anchor`. `clearance` is the distance from
    /// the anchor to the near edge of the label (the mark's radius plus a gap).
    mutating func draw(_ text: String, at anchor: CGPoint, direction: Direction, clearance: CGFloat,
                       force: Bool, in ctx: GraphicsContext) {
        let resolved = ctx.resolve(Text(text).font(Self.font).foregroundColor(Theme.Colors.plateInk))
        let textSize = resolved.measure(in: CGSize(width: 260, height: 60))
        let size = CGSize(width: textSize.width + 2 * Self.padX, height: textSize.height + 2 * Self.padY)
        let candidates = Self.candidates(size: size, anchor: anchor, direction: direction, clearance: clearance)
        var chosen = candidates.first { rect in
            bounds.contains(rect) && !occupied.contains { $0.intersects(rect.insetBy(dx: -2, dy: -2)) }
        }
        if chosen == nil, force, let first = candidates.first {
            chosen = first.clamped(to: bounds)
        }
        guard let rect = chosen else { return }
        occupied.append(rect)

        // A leader line when the label had to move away from its point.
        let nearest = CGPoint(x: min(max(anchor.x, rect.minX), rect.maxX), y: min(max(anchor.y, rect.minY), rect.maxY))
        let distance = hypot(nearest.x - anchor.x, nearest.y - anchor.y)
        if distance > clearance + 6 {
            let dx = nearest.x - anchor.x, dy = nearest.y - anchor.y
            let start = CGPoint(x: anchor.x + dx / distance * (clearance - 2), y: anchor.y + dy / distance * (clearance - 2))
            var leader = Path()
            leader.move(to: start)
            leader.addLine(to: nearest)
            ctx.stroke(leader, with: .color(Theme.Colors.plate.opacity(0.7)), lineWidth: 3)
            ctx.stroke(leader, with: .color(Theme.Colors.plateInk.opacity(0.85)), lineWidth: 1)
        }
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Theme.Colors.plate.opacity(0.8)))
        ctx.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Spots in order of preference: beside the point on its own side, a little higher or
    /// lower, then further out; then the other axis as a last resort.
    private static func candidates(size: CGSize, anchor: CGPoint, direction: Direction, clearance: CGFloat) -> [CGRect] {
        let w = size.width, h = size.height
        func lateral(_ sign: CGFloat) -> [CGRect] {
            let dys: [CGFloat] = [0, -(h / 2 + 4), h / 2 + 4, -(h + 8), h + 8, -(1.5 * h + 12), 1.5 * h + 12]
            return pushes.flatMap { push in
                dys.map { dy in
                    let x = sign < 0 ? anchor.x - clearance - push - w : anchor.x + clearance + push
                    return CGRect(x: x, y: anchor.y + dy - h / 2, width: w, height: h)
                }
            }
        }
        func vertical(_ sign: CGFloat) -> [CGRect] {
            let dxs: [CGFloat] = [0, -w / 3, w / 3]
            return pushes.flatMap { push in
                dxs.map { dx in
                    let y = sign < 0 ? anchor.y - clearance - push - h : anchor.y + clearance + push
                    return CGRect(x: anchor.x + dx - w / 2, y: y, width: w, height: h)
                }
            }
        }
        switch direction {
        case .screenLeft: return lateral(-1) + vertical(-1) + vertical(1)
        case .screenRight: return lateral(1) + vertical(-1) + vertical(1)
        case .above: return vertical(-1) + lateral(-1) + lateral(1)
        case .below: return vertical(1) + lateral(-1) + lateral(1)
        }
    }
}

private extension CGRect {
    /// This rect moved (not resized) to lie inside `outer` where it can.
    func clamped(to outer: CGRect) -> CGRect {
        var r = self
        r.origin.x = Swift.min(Swift.max(r.minX, outer.minX), Swift.max(outer.minX, outer.maxX - r.width))
        r.origin.y = Swift.min(Swift.max(r.minY, outer.minY), Swift.max(outer.minY, outer.maxY - r.height))
        return r
    }
}
