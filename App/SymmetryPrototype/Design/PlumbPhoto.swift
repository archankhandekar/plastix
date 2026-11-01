import SwiftUI
import SymmetryCore
import UIKit

/// A frontal photo on the square Plate, turned so the patient midline runs straight down
/// the centre. The turn ("Plumb") plays once on first appear. Constructions are drawn by the
/// `overlay` closure in plate coordinates and fade in once the turn has finished.
///
/// When the notch or midline bottom is missing (or they coincide) the photo is shown
/// aspect-fit as taken, with no axis and no overlay.
struct PlumbPhoto<Overlay: View>: View {
    private let image: UIImage
    private let landmarks: LandmarkSet?
    private let showsAxis: Bool
    private let showsSideLabels: Bool
    private let animatesTurn: Bool
    private let practice: Bool
    private let overlay: (PlateGeometry) -> Overlay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticMotion) private var staticMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var progress: Double = 0
    @State private var photoOpacity: Double = 1
    @State private var overlayVisible = false
    @State private var hasAppeared = false

    init(image: UIImage,
         landmarks: LandmarkSet?,
         showsAxis: Bool = true,
         showsSideLabels: Bool = true,
         animatesTurn: Bool = true,
         practice: Bool = false,
         @ViewBuilder overlay: @escaping (PlateGeometry) -> Overlay) {
        self.image = image
        self.landmarks = landmarks
        self.showsAxis = showsAxis
        self.showsSideLabels = showsSideLabels
        self.animatesTurn = animatesTurn
        self.practice = practice
        self.overlay = overlay
    }

    private var labelsAbove: Bool { showsSideLabels && dynamicTypeSize.isAccessibilitySize }
    private var labelsOnPlate: Bool { showsSideLabels && !dynamicTypeSize.isAccessibilitySize }

    /// The size the landmark pixel coordinates refer to.
    private var pixelSize: CGSize {
        if let landmarks, landmarks.imageSize.x > 0, landmarks.imageSize.y > 0 {
            return CGSize(width: landmarks.imageSize.x, height: landmarks.imageSize.y)
        }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if labelsAbove {
                SideLabels()
            }
            plate
        }
        .onAppear(perform: startTurn)
    }

    private var plate: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                if let landmarks, let geometry = PlateGeometry(landmarks: landmarks, size: size) {
                    TurnedPhoto(image: image, pixelSize: pixelSize, geometry: geometry, progress: progress)
                        .opacity(photoOpacity)
                    if showsAxis {
                        Path { p in
                            p.move(to: CGPoint(x: geometry.axisX, y: geometry.notchY))
                            p.addLine(to: CGPoint(x: geometry.axisX, y: geometry.bottomY))
                        }
                        .stroke(Theme.Colors.drapeOnPlate, lineWidth: 2)
                        .opacity(overlayVisible ? 1 : 0)
                    }
                    overlay(geometry)
                        .frame(width: size.width, height: size.height)
                        .opacity(overlayVisible ? 1 : 0)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                }
                topStrip
                    .frame(width: size.width, alignment: .top)
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Theme.Colors.plate)
        .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
    }

    @ViewBuilder
    private var topStrip: some View {
        VStack(spacing: 0) {
            if practice {
                PracticeBand(PracticeBand.photoText, style: .plate)
            }
            if labelsOnPlate {
                SideLabels(onPlate: true)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.plate.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
    }

    private func startTurn() {
        guard !hasAppeared else { return }
        hasAppeared = true
        let animation = Motion.plumb(reduceMotion: reduceMotion, staticMotion: staticMotion)
        guard animatesTurn, let animation, PlateGeometry.canTurn(landmarks) else {
            progress = 1
            overlayVisible = true
            return
        }
        if reduceMotion {
            // Reduce Motion: no turn, a short crossfade into the final state.
            progress = 1
            photoOpacity = 0
            withAnimation(animation) {
                photoOpacity = 1
            } completion: {
                withAnimation(animation) { overlayVisible = true }
            }
            return
        }
        progress = 0
        withAnimation(animation) {
            progress = 1
        } completion: {
            withAnimation(.easeOut(duration: 0.2)) { overlayVisible = true }
        }
    }
}

extension PlumbPhoto where Overlay == EmptyView {
    init(image: UIImage,
         landmarks: LandmarkSet?,
         showsAxis: Bool = true,
         showsSideLabels: Bool = true,
         animatesTurn: Bool = true,
         practice: Bool = false) {
        self.init(image: image,
                  landmarks: landmarks,
                  showsAxis: showsAxis,
                  showsSideLabels: showsSideLabels,
                  animatesTurn: animatesTurn,
                  practice: practice,
                  overlay: { _ in EmptyView() })
    }
}

/// The photo drawn through `PlateGeometry.turnTransform(progress:)`. Animatable, so the
/// turn interpolates the rotation rather than crossfading two images.
private struct TurnedPhoto: View, Animatable {
    let image: UIImage
    let pixelSize: CGSize
    let geometry: PlateGeometry
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in
            ctx.concatenate(geometry.turnTransform(progress: progress))
            ctx.draw(Image(uiImage: image), in: CGRect(origin: .zero, size: pixelSize))
        }
        .accessibilityHidden(true)
    }
}
