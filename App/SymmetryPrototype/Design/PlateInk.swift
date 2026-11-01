import SwiftUI

/// Drawing helpers for constructions on the Plate. Every helper takes the context by value
/// and changes only its own copy, so callers never see opacity, clip or dash leak out.
///
/// Grammar: hand-placed marks are violet (`markerOnPlate`) with a 2pt Plate halo, and the
/// shape carries the point type. Derived geometry is Drape blue (`drapeOnPlate`). The white
/// caliper is always the difference itself.
enum PlateInk {
    private static let haloWidth: CGFloat = 2

    // MARK: Hand-placed marks

    /// A nipple: a 16pt open ring with a 3pt stroke and a 3pt centre dot, so the anatomy
    /// under it stays visible.
    static func nipple(in ctx: GraphicsContext, at point: CGPoint, opacity: Double = 1) {
        var c = ctx
        c.opacity *= opacity
        let ring = Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
        let dot = Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
        c.stroke(ring, with: .color(Theme.Colors.plate), lineWidth: 3 + 2 * haloWidth)
        let dotHalo = Path(ellipseIn: CGRect(x: point.x - 1.5 - haloWidth, y: point.y - 1.5 - haloWidth,
                                             width: 3 + 2 * haloWidth, height: 3 + 2 * haloWidth))
        c.fill(dotHalo, with: .color(Theme.Colors.plate))
        c.stroke(ring, with: .color(Theme.Colors.markerOnPlate), lineWidth: 3)
        c.fill(dot, with: .color(Theme.Colors.markerOnPlate))
    }

    /// A fold lowest point: a 14pt downward triangle centred on the point.
    static func fold(in ctx: GraphicsContext, at point: CGPoint, opacity: Double = 1) {
        var c = ctx
        c.opacity *= opacity
        var tri = Path()
        tri.move(to: CGPoint(x: point.x - 7, y: point.y - 6))
        tri.addLine(to: CGPoint(x: point.x + 7, y: point.y - 6))
        tri.addLine(to: CGPoint(x: point.x, y: point.y + 7))
        tri.closeSubpath()
        c.stroke(tri, with: .color(Theme.Colors.plate), style: StrokeStyle(lineWidth: 2 * haloWidth, lineJoin: .round))
        c.fill(tri, with: .color(Theme.Colors.markerOnPlate))
    }

    /// The sternal notch or the midline bottom: a 12pt filled disc.
    static func midlinePoint(in ctx: GraphicsContext, at point: CGPoint, opacity: Double = 1) {
        var c = ctx
        c.opacity *= opacity
        let disc = Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
        c.stroke(disc, with: .color(Theme.Colors.plate), lineWidth: 2 * haloWidth)
        c.fill(disc, with: .color(Theme.Colors.markerOnPlate))
    }

    // MARK: Derived geometry

    /// A height guide: 1.5pt Drape, dashed [6, 4] for the patient-right guide.
    static func guide(in ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, dashed: Bool = false, opacity: Double = 1) {
        var c = ctx
        c.opacity *= opacity
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        c.stroke(p, with: .color(Theme.Colors.drapeOnPlate),
                 style: StrokeStyle(lineWidth: 1.5, lineCap: .butt, dash: dashed ? [6, 4] : []))
    }

    /// A nipple-to-midline bracket: 2pt Drape with 8pt end ticks across the line.
    static func bracket(in ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, opacity: Double = 1) {
        var c = ctx
        c.opacity *= opacity
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
        // Unit normal, half a tick long.
        let nx = -dy / len * 4, ny = dx / len * 4
        for end in [a, b] {
            p.move(to: CGPoint(x: end.x - nx, y: end.y - ny))
            p.addLine(to: CGPoint(x: end.x + nx, y: end.y + ny))
        }
        c.stroke(p, with: .color(Theme.Colors.drapeOnPlate), lineWidth: 2)
    }

    // MARK: The difference

    /// A vertical white caliper from y1 to y2 at x, with 10pt end ticks and ± whiskers at
    /// `whiskerY` (two short ticks `whiskerHalf` above and below). Hollow (dashed) when the
    /// difference is within its ±. Collapses to a single 16pt tick when the ends are within 6pt.
    static func caliperVertical(in ctx: GraphicsContext,
                                x: CGFloat,
                                y1: CGFloat,
                                y2: CGFloat,
                                whiskerY: CGFloat? = nil,
                                whiskerHalf: CGFloat = 0,
                                hollow: Bool = false,
                                opacity: Double = 1) {
        var c = ctx
        c.opacity *= opacity
        let style = caliperStyle(hollow: hollow)
        var p = Path()
        if abs(y2 - y1) < 6 {
            let y = (y1 + y2) / 2
            p.move(to: CGPoint(x: x - 8, y: y))
            p.addLine(to: CGPoint(x: x + 8, y: y))
        } else {
            p.move(to: CGPoint(x: x, y: y1))
            p.addLine(to: CGPoint(x: x, y: y2))
            for y in [y1, y2] {
                p.move(to: CGPoint(x: x - 5, y: y))
                p.addLine(to: CGPoint(x: x + 5, y: y))
            }
        }
        haloed(c, p, style: style)
        if let whiskerY, whiskerHalf > 0 {
            var w = Path()
            for y in [whiskerY - whiskerHalf, whiskerY + whiskerHalf] {
                w.move(to: CGPoint(x: x - 3, y: y))
                w.addLine(to: CGPoint(x: x + 3, y: y))
            }
            haloed(c, w, style: StrokeStyle(lineWidth: 1.5))
        }
    }

    /// A horizontal white caliper from x1 to x2 at y; the horizontal twin of `caliperVertical`.
    static func caliperHorizontal(in ctx: GraphicsContext,
                                  y: CGFloat,
                                  x1: CGFloat,
                                  x2: CGFloat,
                                  whiskerX: CGFloat? = nil,
                                  whiskerHalf: CGFloat = 0,
                                  hollow: Bool = false,
                                  opacity: Double = 1) {
        var c = ctx
        c.opacity *= opacity
        let style = caliperStyle(hollow: hollow)
        var p = Path()
        if abs(x2 - x1) < 6 {
            let x = (x1 + x2) / 2
            p.move(to: CGPoint(x: x, y: y - 8))
            p.addLine(to: CGPoint(x: x, y: y + 8))
        } else {
            p.move(to: CGPoint(x: x1, y: y))
            p.addLine(to: CGPoint(x: x2, y: y))
            for x in [x1, x2] {
                p.move(to: CGPoint(x: x, y: y - 5))
                p.addLine(to: CGPoint(x: x, y: y + 5))
            }
        }
        haloed(c, p, style: style)
        if let whiskerX, whiskerHalf > 0 {
            var w = Path()
            for x in [whiskerX - whiskerHalf, whiskerX + whiskerHalf] {
                w.move(to: CGPoint(x: x, y: y - 3))
                w.addLine(to: CGPoint(x: x, y: y + 3))
            }
            haloed(c, w, style: StrokeStyle(lineWidth: 1.5))
        }
    }

    private static func caliperStyle(hollow: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: 2, lineCap: .butt, dash: hollow ? [4, 3] : [])
    }

    /// Strokes in caliper white over a thin Plate halo so it reads on any part of the photo.
    private static func haloed(_ c: GraphicsContext, _ p: Path, style: StrokeStyle) {
        var halo = style
        halo.lineWidth += 2
        halo.dash = []
        c.stroke(p, with: .color(Theme.Colors.plate.opacity(0.7)), style: halo)
        c.stroke(p, with: .color(Theme.Colors.caliper), style: style)
    }

    // MARK: Outlines and fills

    /// A closed outline through `points`. Patient left is solid violet; the mirrored patient
    /// right is dashed [7, 5] Drape.
    static func outline(in ctx: GraphicsContext,
                        points: [CGPoint],
                        color: Color,
                        dashed: Bool,
                        lineWidth: CGFloat = 2.5,
                        opacity: Double = 1) {
        guard points.count >= 2 else { return }
        var c = ctx
        c.opacity *= opacity
        c.stroke(closedPath(points), with: .color(color),
                 style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: dashed ? [7, 5] : []))
    }

    /// A closed path through the points, for outlines and clip regions.
    static func closedPath(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for q in points.dropFirst() { p.addLine(to: q) }
        p.closeSubpath()
        return p
    }

    /// 45-degree hatch lines clipped to `path`.
    static func hatch(in ctx: GraphicsContext, path: Path, color: Color, spacing: CGFloat = 6) {
        var c = ctx
        c.clip(to: path)
        let lines = HatchPattern(spacing: spacing).path(in: path.boundingRect.insetBy(dx: -1, dy: -1))
        c.stroke(lines, with: .color(color), lineWidth: 1)
    }

    // MARK: The midline ruler

    /// Ticks every 0.1 L down the axis from the notch (0) to the midline bottom (1 L):
    /// 8pt minor, 14pt major at 0, 0.5 and 1. Labels sit on the screen-left side of the axis.
    static func axisRuler(in ctx: GraphicsContext, geometry: PlateGeometry, showsLabels: Bool) {
        var ticks = Path()
        for i in 0...10 {
            let y = geometry.notchY + CGFloat(i) / 10 * geometry.pointsPerL
            let half: CGFloat = (i % 5 == 0) ? 7 : 4
            ticks.move(to: CGPoint(x: geometry.axisX - half, y: y))
            ticks.addLine(to: CGPoint(x: geometry.axisX + half, y: y))
        }
        ctx.stroke(ticks, with: .color(Theme.Colors.plate.opacity(0.7)), lineWidth: 3.5)
        ctx.stroke(ticks, with: .color(Theme.Colors.drapeOnPlate), lineWidth: 1.5)

        guard showsLabels else { return }
        let labels: [(String, CGFloat)] = [("0", 0), ("0.5 L", 0.5), ("1 L", 1)]
        for (text, f) in labels {
            let y = geometry.notchY + f * geometry.pointsPerL
            let resolved = ctx.resolve(Text(text).font(.scaleTick).foregroundColor(Theme.Colors.plateGraduation))
            let s = resolved.measure(in: CGSize(width: 200, height: 100))
            let anchor = CGPoint(x: geometry.axisX - 12, y: y)
            let backing = CGRect(x: anchor.x - s.width - 4, y: anchor.y - s.height / 2 - 1,
                                 width: s.width + 8, height: s.height + 2)
            ctx.fill(Path(roundedRect: backing, cornerRadius: 3), with: .color(Theme.Colors.plate.opacity(0.75)))
            ctx.draw(resolved, at: anchor, anchor: .trailing)
        }
    }
}
