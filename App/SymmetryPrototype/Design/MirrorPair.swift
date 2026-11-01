import SwiftUI
import UIKit

enum MirrorPairMode: String, CaseIterable, Hashable {
    case sideBySide, wipe, switchSide
}

/// The two oblique photos facing the patient: the right oblique in the screen-left column
/// (flipped by default, so both sides face the same way) and the left oblique in the
/// screen-right column. Descriptive only: no numbers anywhere. The flipped image is for
/// display and is never saved or exported.
struct MirrorPair: View {
    private let patientRightImage: UIImage?
    private let patientLeftImage: UIImage?
    private let flipPatientRight: Bool
    private let mode: MirrorPairMode
    @Binding private var wipeFraction: CGFloat
    @Binding private var showingPatientRight: Bool
    private let practice: Bool

    static let wipeStep: CGFloat = 0.1
    static let wipeRange: ClosedRange<CGFloat> = 0.1...0.9

    init(patientRightImage: UIImage?,
         patientLeftImage: UIImage?,
         flipPatientRight: Bool,
         mode: MirrorPairMode,
         wipeFraction: Binding<CGFloat>,
         showingPatientRight: Binding<Bool>,
         practice: Bool = false) {
        self.patientRightImage = patientRightImage
        self.patientLeftImage = patientLeftImage
        self.flipPatientRight = flipPatientRight
        self.mode = mode
        self._wipeFraction = wipeFraction
        self._showingPatientRight = showingPatientRight
        self.practice = practice
    }

    /// Obliques are portrait; both columns share this shape so the photos sit at the same height.
    private let photoAspect: CGFloat = 3.0 / 4.0

    private var rightCaption: String {
        flipPatientRight ? "Right oblique, flipped" : "Right oblique, as taken"
    }
    private let leftCaption = "Left oblique"
    private let rightMissing = "Not taken: right oblique."
    private let leftMissing = "Not taken: left oblique."

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if practice {
                PracticeBand(PracticeBand.photoText, style: .plate)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
            }
            switch mode {
            case .sideBySide: sideBySide
            case .wipe: wipe
            case .switchSide: switchSide
            }
        }
    }

    // MARK: Side by side

    private var sideBySide: some View {
        FacingColumns(showsAxis: true, spacing: 8) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                photo(patientRightImage, flipped: flipPatientRight, missing: rightMissing)
                caption(rightCaption)
            }
        } patientLeft: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                photo(patientLeftImage, flipped: false, missing: leftMissing)
                caption(leftCaption)
            }
        }
    }

    // MARK: Wipe

    private var wipe: some View {
        VStack(spacing: Theme.Spacing.s) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let dividerX = width * clamped(wipeFraction)
                ZStack(alignment: .topLeading) {
                    Theme.Colors.plate
                    image(patientLeftImage, flipped: false, missing: leftMissing)
                    image(patientRightImage, flipped: flipPatientRight, missing: rightMissing)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: dividerX)
                        }
                    HStack(alignment: .top) {
                        plateCaption(rightCaption)
                        Spacer(minLength: Theme.Spacing.s)
                        plateCaption(leftCaption)
                    }
                    .padding(Theme.Spacing.s)
                    Rectangle()
                        .fill(Theme.Colors.drapeOnPlate)
                        .frame(width: 2, height: proxy.size.height)
                        .offset(x: dividerX - 1)
                        .accessibilityHidden(true)
                    grip
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wipe"))
                            .onChanged { value in
                                guard width > 0 else { return }
                                wipeFraction = clamped(value.location.x / width)
                            })
                        .position(x: dividerX, y: proxy.size.height / 2)
                }
                .coordinateSpace(name: "wipe")
            }
            .aspectRatio(photoAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))

            HStack(spacing: Theme.Spacing.s) {
                Button("Move the divider left") { step(-Self.wipeStep) }
                    .buttonStyle(PlateButtonStyle())
                    .frame(maxWidth: .infinity)
                Button("Move the divider right") { step(Self.wipeStep) }
                    .buttonStyle(PlateButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            .padding(Theme.Spacing.s)
            .background(Theme.Colors.plate, in: RoundedRectangle(cornerRadius: Theme.photoRadius))
        }
    }

    private var grip: some View {
        Circle()
            .fill(Theme.Colors.plate.opacity(0.75))
            .overlay(Circle().strokeBorder(Theme.Colors.drapeOnPlate, lineWidth: 2))
            .overlay(
                Image(systemName: "arrow.left.and.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.plateInk)
            )
            .frame(width: Theme.tapTarget, height: Theme.tapTarget)
            .contentShape(Circle())
            .accessibilityElement()
            .accessibilityLabel("Divider")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(Self.wipeStep)
                case .decrement: step(-Self.wipeStep)
                @unknown default: break
                }
            }
    }

    private func step(_ delta: CGFloat) {
        // Round to the step grid so repeated taps land on 0.1, 0.2, ... exactly.
        let next = ((wipeFraction + delta) * 10).rounded() / 10
        wipeFraction = clamped(next)
    }

    private func clamped(_ f: CGFloat) -> CGFloat {
        min(Self.wipeRange.upperBound, max(Self.wipeRange.lowerBound, f))
    }

    // MARK: Switch side

    private var switchSide: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if showingPatientRight {
                photo(patientRightImage, flipped: flipPatientRight, missing: rightMissing)
            } else {
                photo(patientLeftImage, flipped: false, missing: leftMissing)
            }
            Text(showingCaption)
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show the other side") { showingPatientRight.toggle() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var showingCaption: String {
        if showingPatientRight {
            return flipPatientRight
                ? "Showing: patient right, right oblique flipped"
                : "Showing: patient right, right oblique as taken"
        }
        return "Showing: patient left, left oblique"
    }

    // MARK: Pieces

    private func photo(_ uiImage: UIImage?, flipped: Bool, missing: String) -> some View {
        Color.clear
            .aspectRatio(photoAspect, contentMode: .fit)
            .overlay { image(uiImage, flipped: flipped, missing: missing) }
            .background(Theme.Colors.plate)
            .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius))
    }

    @ViewBuilder
    private func image(_ uiImage: UIImage?, flipped: Bool, missing: String) -> some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .scaleEffect(x: flipped ? -1 : 1, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        } else {
            Text(missing)
                .font(.body)
                .foregroundStyle(Theme.Colors.plateInk)
                .multilineTextAlignment(.center)
                .padding(Theme.Spacing.s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.plate)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.support)
            .foregroundStyle(Theme.Colors.graduation)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func plateCaption(_ text: String) -> some View {
        Text(text)
            .font(.support)
            .foregroundStyle(Theme.Colors.plateInk)
            .padding(.horizontal, Theme.Spacing.xs)
            .background(Theme.Colors.plate.opacity(0.7), in: RoundedRectangle(cornerRadius: 2))
    }
}
