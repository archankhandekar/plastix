import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Baseline versus current capture set, per angle. Frontal views get registered
/// landmark overlays and metric deltas; oblique views are shown side by side only.
struct ComparisonView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    let sessionID: UUID

    @State private var baselineID: UUID?
    @State private var currentID: UUID?

    private var session: StudySession? { store.session(id: sessionID) }
    private var candidates: [CaptureSet] { session?.orderedCaptureSets.filter { $0.frontal != nil } ?? [] }

    private func set(_ id: UUID?) -> CaptureSet? { id.flatMap { session?.captureSet(id: $0) } }

    private func label(_ set: CaptureSet) -> String {
        let index = (candidates.firstIndex { $0.id == set.id } ?? 0) + 1
        return "\(index). \(set.stage.label)"
    }

    var body: some View {
        if let session {
            List {
                Section("Capture sets") {
                    Picker("Baseline", selection: $baselineID) {
                        ForEach(candidates) { s in Text(label(s)).tag(Optional(s.id)) }
                    }
                    Picker("Current", selection: $currentID) {
                        ForEach(candidates) { s in Text(label(s)).tag(Optional(s.id)) }
                    }
                }
                if let b = set(baselineID), let c = set(currentID), b.id != c.id {
                    if b.positioning != c.positioning {
                        Section {
                            Label("Positioning differs between these sets. Differences may reflect posture, not anatomy.", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(Theme.Colors.caution)
                        }
                    }
                    ForEach(ViewAngle.allCases) { angle in
                        Section(angle.displayName) {
                            AngleComparison(session: session, baseline: b, current: c, angle: angle)
                        }
                    }
                } else {
                    Section { Text("Choose two different capture sets that both have a frontal view.").foregroundStyle(Theme.Colors.slate) }
                }
                Section { ResearchNoticeBanner() }
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if baselineID == nil { baselineID = candidates.first?.id }
                if currentID == nil { currentID = candidates.last?.id }
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
        }
    }
}

struct AngleComparison: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    let session: StudySession
    let baseline: CaptureSet
    let current: CaptureSet
    let angle: ViewAngle

    private var baseCapture: Capture? { baseline.captures[angle] }
    private var curCapture: Capture? { current.captures[angle] }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            imagePane("Baseline", baseCapture)
            imagePane("Current", curCapture)
        }
        if angle == .frontal {
            frontalComparison
        } else {
            Text("Oblique views are compared descriptively: look at the silhouette and upper and lower pole shape. No bilateral metric is defined because the two sides are never in one oblique image.")
                .font(.footnote).foregroundStyle(Theme.Colors.slate)
            FlagList(flags: unique((baseCapture?.reliabilityFlags ?? []) + (curCapture?.reliabilityFlags ?? [])))
        }
    }

    @ViewBuilder
    private func imagePane(_ title: String, _ capture: Capture?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(.caption).foregroundStyle(Theme.Colors.slate)
            if let capture, let image = store.image(for: capture, in: session) {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if let q = capture.quality, !q.passed {
                    Label(q.failures.map(\.displayText).joined(separator: ", "), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(Theme.Colors.caution)
                }
            } else {
                Theme.Colors.hairline.frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(Text("Not captured").font(.caption).foregroundStyle(Theme.Colors.slate))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var frontalComparison: some View {
        if let b = baseCapture, let c = curCapture, let bl = b.landmarks, let cl = c.landmarks,
           let bm = b.frontalMetrics(sigma: settings.landmarkSigmaRatio), let cm = c.frontalMetrics(sigma: settings.landmarkSigmaRatio) {
            let reg = Registration.register(cl, to: bl, maxResidualRatio: settings.maxResidualRatio)
            let comparison = Comparator.compare(baseline: bm, current: cm, registration: reg, angle: .frontal,
                                                captureFlags: b.reliabilityFlags + c.reliabilityFlags)
            if let image = store.image(for: b, in: session) {
                LandmarkOverlayImage(image: image, baseline: bl, current: cl, transform: reg?.transform, dimmed: !(reg?.isReliable ?? false))
                    .frame(maxHeight: 360)
                Text("Baseline image with baseline landmarks (filled) and registered current landmarks (hollow).")
                    .font(.caption).foregroundStyle(Theme.Colors.slate)
            }
            if let reg {
                Text(String(format: "Registration residual %.3f L over %d landmarks (limit %.2f L), scale %.2f, rotation %.1f°",
                            reg.rmsResidualRatio, reg.sharedLandmarkCount, reg.maxResidualRatio, reg.transform.scale, reg.transform.rotation * 180 / .pi))
                    .font(.metricSmall).foregroundStyle(reg.isReliable ? Theme.Colors.slate : Theme.Colors.unreliable)
            }
            ForEach(comparison.deltas, id: \.name) { MetricDeltaRow(delta: $0) }
            FlagList(flags: comparison.flags)
            Text("Values are fractions of the reference length L (sternal notch to midline bottom). Change = current − baseline, with uncertainties combined.")
                .font(.caption).foregroundStyle(Theme.Colors.slate)
        } else {
            Text("Place landmarks on both frontal images to see metrics.")
                .font(.footnote).foregroundStyle(Theme.Colors.caution)
        }
    }

    private func unique(_ flags: [ReliabilityFlag]) -> [ReliabilityFlag] {
        var out: [ReliabilityFlag] = []
        for f in flags where !out.contains(f) { out.append(f) }
        return out
    }
}

/// An image with two landmark sets drawn in its pixel space.
struct LandmarkOverlayImage: View {
    let image: UIImage
    let baseline: LandmarkSet
    let current: LandmarkSet?
    let transform: SimilarityTransform?
    let dimmed: Bool

    var body: some View {
        GeometryReader { geo in
            let fit = fitRect(in: geo.size)
            ZStack {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                Canvas { ctx, _ in
                    draw(ctx, set: baseline, transform: nil, filled: true, fit: fit)
                    if let current, let transform {
                        draw(ctx, set: current, transform: transform, filled: false, fit: fit)
                    }
                }
                .opacity(dimmed ? 0.6 : 1)
            }
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
    }

    private func fitRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func toView(_ p: Point2D, fit: CGRect) -> CGPoint {
        CGPoint(x: fit.minX + CGFloat(p.x) * fit.width / image.size.width,
                y: fit.minY + CGFloat(p.y) * fit.height / image.size.height)
    }

    private func draw(_ ctx: GraphicsContext, set: LandmarkSet, transform: SimilarityTransform?, filled: Bool, fit: CGRect) {
        func map(_ p: Point2D) -> CGPoint { toView(transform?.apply(p) ?? p, fit: fit) }
        for contour in [set.leftContour, set.rightContour] where contour.count > 1 {
            var path = Path()
            path.move(to: map(contour[0]))
            for p in contour.dropFirst() { path.addLine(to: map(p)) }
            ctx.stroke(path, with: .color(filled ? .orange : .cyan), style: StrokeStyle(lineWidth: 1.5, dash: filled ? [] : [4, 3]))
        }
        for (_, p) in set.points {
            let v = map(p)
            let r: CGFloat = filled ? 5 : 7
            let rect = CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)
            if filled {
                ctx.fill(Path(ellipseIn: rect), with: .color(.orange))
            } else {
                ctx.stroke(Path(ellipseIn: rect), with: .color(.cyan), lineWidth: 2)
            }
        }
    }
}
