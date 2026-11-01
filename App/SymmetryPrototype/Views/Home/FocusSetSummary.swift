import SwiftUI
import SymmetryCore
import SymmetryModels
import UIKit

/// The focus set's left-right result at the top of session home: the turned frontal photo
/// on the Plate beside the four left-right differences, each with its ±. The photo and
/// every row open the full result (a row opens it focused on that difference).
///
/// At default text sizes the photo and the four rows sit side by side so the whole result
/// fits on the first screen; at larger sizes they stack so no readout has to wrap.
struct FocusSetSummary: View {
    let image: UIImage?
    let landmarks: LandmarkSet?
    let reading: SetReading
    let setIndex: Int
    /// Nil opens the full result; a metric opens it focused on that difference.
    let onOpen: (BilateralMetric?) -> Void
    let onMarkPoints: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Width of the photo when it sits beside the rows.
    private static let sideBySidePhotoWidth: CGFloat = 176
    /// Largest width of the photo when it sits above the rows.
    private static let stackedPhotoWidth: CGFloat = 240

    private var hasAnyPoint: Bool { landmarks.map { !$0.points.isEmpty } ?? false }
    private var sideBySide: Bool { hasAnyPoint && dynamicTypeSize <= .xLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if sideBySide {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    thumbnail
                        .frame(width: Self.sideBySidePhotoWidth)
                    rows
                }
            } else {
                // Stacked: a smaller plate so the differences start on the first screen.
                thumbnail
                    .frame(maxWidth: Self.stackedPhotoWidth)
                    .frame(maxWidth: .infinity)
                if hasAnyPoint {
                    rows
                } else {
                    notMarked
                }
            }
        }
    }

    private var thumbnail: some View {
        SetPlateThumbnail(image: image,
                          landmarks: landmarks,
                          setIndex: setIndex) {
            onOpen(nil)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(reading.readings) { r in
                row(r)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ r: MetricReading) -> some View {
        Button {
            onOpen(r.metric)
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.metric.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if r.measurement != nil {
                        Text(r.readout)
                            .font(.readoutRow)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let side = Self.sideLine(r) {
                            Text(side)
                                .font(.support)
                                .foregroundStyle(Theme.Colors.graduation)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle")
                                .accessibilityHidden(true)
                            Text(r.readout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.support)
                        .foregroundStyle(Theme.Colors.caution)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.support.weight(.semibold))
                    .foregroundStyle(Theme.Colors.graduation)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([r.metric.title, r.readout, r.sentence ?? r.notMeasuredReason]
            .compactMap { $0 }
            .joined(separator: ", "))
        .accessibilityHint("Opens left and right for set \(setIndex), on this difference.")
        .accessibilityAddTraits(.isButton)
    }

    /// No point placed yet: one reason instead of four identical ones.
    private var notMarked: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
                Text(ReadingCopy.notMeasuredReason(for: .nippleHeight, missing: LandmarkType.allCases, flags: []))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.body)
            .foregroundStyle(Theme.Colors.caution)
            .accessibilityElement(children: .combine)
            Button("Mark points", action: onMarkPoints)
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    /// Which patient side the difference points to, by the same rule as the result's
    /// sentences: only when the value is larger than its ±. Nil for the outline overlap.
    static func sideLine(_ r: MetricReading) -> String? {
        guard let m = r.measurement else { return nil }
        let v = m.value, u = m.uncertainty
        switch r.metric {
        case .nippleHeight, .foldHeight:
            if v > u { return "Patient left lower" }
            if v < -u { return "Patient right lower" }
            return "Smaller than its ±"
        case .nippleMidline:
            if v > u { return "Patient left farther" }
            if v < -u { return "Patient right farther" }
            return "Smaller than its ±"
        case .outlineOverlap:
            return "1 means they coincide"
        }
    }
}
