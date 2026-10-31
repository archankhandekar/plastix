import SwiftUI
import SymmetryCore
import SymmetryModels

/// The session's photo sets in order, one `CaptureSetCard` each. A thin `ForEach`; the
/// caller provides the section heading and the empty state.
struct TimelineView: View {
    let session: StudySession
    let sigma: Double
    let onCaptureMissing: (CaptureSet, Int, [ViewAngle]) -> Void
    let onMarkPoints: (CaptureSet, Int, Capture) -> Void

    var body: some View {
        ForEach(Array(session.orderedCaptureSets.enumerated()), id: \.element.id) { offset, set in
            let index = offset + 1
            CaptureSetCard(session: session,
                           set: set,
                           status: CaptureSetStatus(set: set, index: index, sigma: sigma),
                           sigma: sigma,
                           onCaptureMissing: onCaptureMissing,
                           onMarkPoints: onMarkPoints)
        }
    }
}

/// Screen 7: one photo set. Only the header navigates (to the set screen); the per-set
/// action button and the measurements disclosure sit outside that link.
struct CaptureSetCard: View {
    @EnvironmentObject private var store: SessionStore
    let session: StudySession
    let set: CaptureSet
    let status: CaptureSetStatus
    let sigma: Double
    let onCaptureMissing: (CaptureSet, Int, [ViewAngle]) -> Void
    let onMarkPoints: (CaptureSet, Int, Capture) -> Void

    @State private var isExpanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            NavigationLink {
                ReviewView(sessionID: session.id, setID: set.id)
            } label: {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(status.title)
                            .font(.stepTitle)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(set.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.slate)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.slate)
                }
                .tapTarget()
            }
            .buttonStyle(.plain)

            Text(status.line)
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)

            // Three 88pt columns side by side (8pt gaps fit a 375pt phone); stacked vertically
            // at accessibility text sizes so captions and badges have room.
            thumbnailLayout {
                ForEach(ViewAngle.allCases) { angle in
                    let capture = set.captures[angle]
                    Thumbnail(image: capture.flatMap { store.image(for: $0, in: session) },
                              label: angle.displayName,
                              badges: badges(for: capture))
                }
            }

            if let action = status.nextAction {
                switch action {
                case .captureMissing(_, _, let angles, let title, _):
                    Button(title) { onCaptureMissing(set, status.index, angles) }
                        .buttonStyle(PrimaryButtonStyle())
                case .markPoints(_, _, let capture, let title, _):
                    Button(title) { onMarkPoints(set, status.index, capture) }
                        .buttonStyle(SecondaryButtonStyle())
                default:
                    EmptyView()
                }
            }

            if let frontal = set.frontal,
               let landmarks = frontal.landmarks,
               landmarks.isComplete,
               let metrics = frontal.frontalMetrics(sigma: sigma) {
                measurements(metrics: metrics, landmarks: landmarks)
            }
        }
        .cardStyle()
    }

    // MARK: - Pieces

    private var thumbnailLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.s))
    }

    /// "Warning" when the quality check ran and failed, "Not checked" when it never ran,
    /// "Marked" when all six points are placed. Nothing for a missing photo.
    private func badges(for capture: Capture?) -> [String] {
        guard let capture else { return [] }
        var result: [String] = []
        if let quality = capture.quality {
            if !quality.passed { result.append("Warning") }
        } else {
            result.append("Not checked")
        }
        if capture.landmarks?.isComplete == true { result.append("Marked") }
        return result
    }

    private func measurements(metrics: FrontalMetrics, landmarks: LandmarkSet) -> some View {
        let hasContours = !landmarks.leftContour.isEmpty && !landmarks.rightContour.isEmpty
        return DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(metrics.namedMetrics.enumerated()), id: \.offset) { _, metric in
                    MetricRow(name: metric.name,
                              measurement: metric.measurement,
                              explanation: MetricGlossary.meaning(for: metric.name),
                              reason: MetricGlossary.reason(flags: metrics.flags,
                                                            missing: landmarks.missing,
                                                            hasContours: hasContours,
                                                            metricName: metric.name))
                }
            }
            .padding(.top, Theme.Spacing.s)
        } label: {
            Text(isExpanded ? "Hide measurements" : "Show measurements")
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .tapTarget()
        }
    }

    /// 88x116 photo with its caption and text badges; "Not taken" when there is no photo.
    struct Thumbnail: View {
        let image: UIImage?
        let label: String
        let badges: [String]
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Theme.Colors.hairline
                            Text("Not taken")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.ink)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(width: 88, height: 116)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.subheadline)
                        .foregroundStyle(color(for: badge))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(color(for: badge), lineWidth: 1))
                }
            }
            // Column matches the 88pt photo; at accessibility sizes it takes the full width.
            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 88, alignment: .leading)
            .accessibilityElement(children: .combine)
        }

        private func color(for badge: String) -> Color {
            switch badge {
            case "Warning": return Theme.Colors.caution
            case "Marked": return Theme.Colors.accent
            default: return Theme.Colors.slate
            }
        }
    }
}
