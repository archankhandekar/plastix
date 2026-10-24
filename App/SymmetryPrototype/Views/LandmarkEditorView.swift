import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// Place and adjust landmarks and contours on one image. Tap places the selected
/// landmark; drag moves the nearest one; contour mode appends points while dragging.
struct LandmarkEditorView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    let setID: UUID
    let captureID: UUID

    enum Mode: Hashable { case point(LandmarkType), leftContour, rightContour }

    @State private var landmarks: LandmarkSet?
    @State private var mode: Mode = .point(.sternalNotch)
    @State private var loaded = false

    private var session: StudySession? { store.session(id: sessionID) }
    private var capture: Capture? { session?.captureSet(id: setID)?.captures.values.first { $0.id == captureID } }

    var body: some View {
        Group {
            if let session, let capture, let image = store.image(for: capture, in: session) {
                VStack(spacing: Theme.Spacing.s) {
                    LandmarkCanvas(image: image, landmarks: Binding(get: { landmarks ?? LandmarkSet(imageSize: capture.imageSize) },
                                                                    set: { landmarks = $0 }),
                                   mode: mode) { placed in advance(after: placed) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Colors.capture)
                    modeChips
                    metricsPreview(capture: capture)
                }
                .onAppear { if !loaded { landmarks = capture.landmarks ?? LandmarkSet(imageSize: capture.imageSize); loaded = true } }
                .navigationTitle(capture.angle.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(capture, in: session) } }
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Clear selected", action: clearSelected)
                            Button("Undo last contour point", action: undoContourPoint)
                            Button("Clear all landmarks", role: .destructive) { landmarks = LandmarkSet(imageSize: capture.imageSize) }
                        } label: { Label("Edit", systemImage: "ellipsis.circle") }
                    }
                }
            } else {
                ContentUnavailableView("Image not available", systemImage: "photo")
            }
        }
    }

    private var modeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(LandmarkType.allCases) { type in
                    chip(type.shortName, selected: mode == .point(type), placed: landmarks?[type] != nil) { mode = .point(type) }
                }
                chip("L contour", selected: mode == .leftContour, placed: (landmarks?.leftContour.count ?? 0) >= ContourOverlap.minimumPoints) { mode = .leftContour }
                chip("R contour", selected: mode == .rightContour, placed: (landmarks?.rightContour.count ?? 0) >= ContourOverlap.minimumPoints) { mode = .rightContour }
            }
            .padding(.horizontal, Theme.Spacing.m)
        }
    }

    private func chip(_ title: String, selected: Bool, placed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if placed { Image(systemName: "checkmark") }
                Text(title)
            }
            .font(.footnote.weight(selected ? .semibold : .regular))
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 40)
            .background(selected ? Theme.Colors.accent : Theme.Colors.surface, in: Capsule())
            .foregroundStyle(selected ? .white : Theme.Colors.ink)
            .overlay(Capsule().stroke(Theme.Colors.hairline))
        }
        .accessibilityLabel("\(title)\(placed ? ", placed" : "")")
    }

    @ViewBuilder
    private func metricsPreview(capture: Capture) -> some View {
        if capture.angle == .frontal, let landmarks {
            let m = FrontalMetricsCalculator.compute(landmarks, landmarkSigmaRatio: settings.landmarkSigmaRatio)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(m.namedMetrics.prefix(5), id: \.name) { item in
                    MetricRow(name: item.name, measurement: item.measurement)
                }
                FlagList(flags: m.flags)
            }
            .font(.footnote)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.s)
        } else if capture.angle != .frontal {
            Text("Oblique views are compared descriptively. Landmarks here are for overlay only.")
                .font(.footnote).foregroundStyle(Theme.Colors.slate)
                .padding(.horizontal, Theme.Spacing.m).padding(.bottom, Theme.Spacing.s)
        }
    }

    /// After placing a point landmark, move to the next missing one.
    private func advance(after placed: Mode) {
        guard case .point = placed, let landmarks, let next = landmarks.missing.first else { return }
        mode = .point(next)
    }

    private func clearSelected() {
        switch mode {
        case .point(let t): landmarks?[t] = nil
        case .leftContour: landmarks?.leftContour = []
        case .rightContour: landmarks?.rightContour = []
        }
    }

    private func undoContourPoint() {
        switch mode {
        case .leftContour: _ = landmarks?.leftContour.popLast()
        case .rightContour: _ = landmarks?.rightContour.popLast()
        case .point: break
        }
    }

    private func save(_ capture: Capture, in session: StudySession) {
        guard var set = session.captureSet(id: setID) else { return }
        var updated = capture
        updated.landmarks = landmarks
        set.update(updated)
        var s = session
        s.update(set)
        store.save(s)
        dismiss()
    }
}

/// The image with its landmarks, handling placement gestures and a loupe while dragging.
struct LandmarkCanvas: View {
    let image: UIImage
    @Binding var landmarks: LandmarkSet
    let mode: LandmarkEditorView.Mode
    let onPlaced: (LandmarkEditorView.Mode) -> Void

    @State private var dragging: LandmarkType?
    @State private var dragMoved = false
    @State private var fingerView: CGPoint?
    @State private var lastContourPoint: Point2D?

    private let grabRadius: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let fit = fitRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                Canvas { ctx, _ in
                    draw(ctx, fit: fit)
                }
                .allowsHitTesting(false)
                if let finger = fingerView {
                    Loupe(image: image, fit: fit, center: finger)
                        .position(x: finger.x, y: max(70, finger.y - 110))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in handleChange(value, fit: fit) }
                    .onEnded { value in handleEnd(value, fit: fit) }
            )
        }
    }

    // MARK: - Coordinates

    private func fitRect(in size: CGSize) -> CGRect {
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / iw, size.height / ih)
        let w = iw * scale, h = ih * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func toPixel(_ p: CGPoint, fit: CGRect) -> Point2D {
        let sx = image.size.width / fit.width, sy = image.size.height / fit.height
        let x = min(max(p.x, fit.minX), fit.maxX), y = min(max(p.y, fit.minY), fit.maxY)
        return Point2D(x: Double((x - fit.minX) * sx), y: Double((y - fit.minY) * sy))
    }

    private func toView(_ p: Point2D, fit: CGRect) -> CGPoint {
        let sx = fit.width / image.size.width, sy = fit.height / image.size.height
        return CGPoint(x: fit.minX + CGFloat(p.x) * sx, y: fit.minY + CGFloat(p.y) * sy)
    }

    // MARK: - Gestures

    private func handleChange(_ value: DragGesture.Value, fit: CGRect) {
        fingerView = value.location
        switch mode {
        case .point(let selected):
            if dragging == nil, !dragMoved {
                // Grab an existing landmark only when it is the selected one, or when the
                // selected one is already placed; otherwise the gesture places the selection.
                if let near = nearestLandmark(to: value.startLocation, fit: fit),
                   near == selected || landmarks[selected] != nil {
                    dragging = near
                }
            }
            if value.translation.width.magnitude > 4 || value.translation.height.magnitude > 4 { dragMoved = true }
            if let d = dragging, dragMoved { landmarks[d] = toPixel(value.location, fit: fit) }
        case .leftContour, .rightContour:
            let p = toPixel(value.location, fit: fit)
            let minSpacing = Double(image.size.width) / 150
            if let last = lastContourPoint, last.distance(to: p) < minSpacing { return }
            lastContourPoint = p
            if mode == .leftContour { landmarks.leftContour.append(p) } else { landmarks.rightContour.append(p) }
        }
    }

    private func handleEnd(_ value: DragGesture.Value, fit: CGRect) {
        defer { dragging = nil; dragMoved = false; fingerView = nil; lastContourPoint = nil }
        guard case .point(let type) = mode else { onPlaced(mode); return }
        // A tap, or a drag that started on empty image, places the selected landmark where
        // the finger lifted. Gloved taps often travel a few points; that still places.
        if dragging == nil {
            landmarks[type] = toPixel(value.location, fit: fit)
            onPlaced(mode)
        }
    }

    private func nearestLandmark(to p: CGPoint, fit: CGRect) -> LandmarkType? {
        var best: (LandmarkType, CGFloat)?
        for (type, pt) in landmarks.points {
            let v = toView(pt, fit: fit)
            let d = hypot(v.x - p.x, v.y - p.y)
            if d <= grabRadius, best == nil || d < best!.1 { best = (type, d) }
        }
        return best?.0
    }

    // MARK: - Drawing

    private func draw(_ ctx: GraphicsContext, fit: CGRect) {
        for (contour, color) in [(landmarks.leftContour, Color.orange), (landmarks.rightContour, Color.yellow)] where contour.count > 1 {
            var path = Path()
            path.move(to: toView(contour[0], fit: fit))
            for p in contour.dropFirst() { path.addLine(to: toView(p, fit: fit)) }
            ctx.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 2)
        }
        if let n = landmarks[.sternalNotch], let b = landmarks[.midlineBottom] {
            var path = Path()
            path.move(to: toView(n, fit: fit)); path.addLine(to: toView(b, fit: fit))
            ctx.stroke(path, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        for (type, p) in landmarks.points {
            let v = toView(p, fit: fit)
            let isLeft = type == .leftNipple || type == .leftIMF
            let color: Color = type == .sternalNotch || type == .midlineBottom ? .white : (isLeft ? .orange : .yellow)
            let r: CGFloat = 7
            ctx.stroke(Path(ellipseIn: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)), with: .color(color), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: v.x - 1.5, y: v.y - 1.5, width: 3, height: 3)), with: .color(color))
            ctx.draw(Text(type.shortName).font(.caption2).foregroundStyle(color), at: CGPoint(x: v.x, y: v.y - r - 8))
        }
    }

    /// Magnified view of the image under the finger.
    struct Loupe: View {
        let image: UIImage
        let fit: CGRect
        let center: CGPoint
        private let diameter: CGFloat = 120
        private let zoom: CGFloat = 2.5

        var body: some View {
            Image(uiImage: image)
                .resizable()
                .frame(width: fit.width * zoom, height: fit.height * zoom)
                .offset(x: -(center.x - fit.minX) * zoom + diameter / 2, y: -(center.y - fit.minY) * zoom + diameter / 2)
                .frame(width: diameter, height: diameter, alignment: .topLeading)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .overlay(Image(systemName: "plus").font(.caption).foregroundStyle(.white))
                .shadow(radius: 4)
        }
    }
}
