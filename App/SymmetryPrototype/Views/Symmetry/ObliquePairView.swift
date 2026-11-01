import SwiftUI
import UIKit

/// The obliques tab: the two oblique photos facing the patient. The right oblique sits in
/// the screen-left "Patient right" column, flipped by default so both sides face the same
/// way; the left oblique sits in the screen-right column as taken. Descriptive only: nothing
/// is measured and no number appears. The flipped image is for display and never saved.
/// Practice photos are marked by the screen's one pinned band and a hatched rule on each
/// plate; this view adds no second banner.
struct ObliquePairView: View {
    private let rightOblique: UIImage?
    private let leftOblique: UIImage?
    private let practice: Bool

    @State private var mode: ObliqueMode
    @State private var flip = true
    @State private var wipeFraction: CGFloat = 0.5
    @State private var showingPatientRight = true

    init(rightOblique: UIImage?, leftOblique: UIImage?, mode: ObliqueMode, practice: Bool) {
        self.rightOblique = rightOblique
        self.leftOblique = leftOblique
        self.practice = practice
        _mode = State(initialValue: mode)
    }

    static func pairMode(_ mode: ObliqueMode) -> MirrorPairMode {
        switch mode {
        case .sideBySide: return .sideBySide
        case .wipe: return .wipe
        case .switchSide: return .switchSide
        }
    }

    private let modeOptions: [(value: ObliqueMode, title: String)] = [
        (.sideBySide, "Side by side"),
        (.wipe, "Wipe"),
        (.switchSide, "Switch side"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            // The view controls come first, so they are found before the photos. The photo
            // captions already say whether the right oblique is flipped.
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SegmentedChoice(modeOptions, selection: $mode)
                ToggleChip("Flip", isOn: $flip)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                // Switch side shows one photo at a time and names its side on the photo.
                if mode != .switchSide {
                    SideLabels()
                }
                MirrorPair(patientRightImage: rightOblique,
                           patientLeftImage: leftOblique,
                           flipPatientRight: flip,
                           mode: Self.pairMode(mode),
                           wipeFraction: $wipeFraction,
                           showingPatientRight: $showingPatientRight,
                           practice: practice)
            }

            Text(ReadingCopy.obliquesNote)
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
