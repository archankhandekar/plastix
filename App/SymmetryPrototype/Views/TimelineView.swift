import SwiftUI
import SymmetryCore
import SymmetryModels

/// Ordered capture sets with stage labels, thumbnails and completeness.
struct TimelineView: View {
    @EnvironmentObject private var store: SessionStore
    let session: StudySession
    let onCaptureMissing: (CaptureSet, [ViewAngle]) -> Void

    var body: some View {
        if session.captureSets.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("No capture sets yet").font(.headline)
                Text("Each set is three views at one operative stage.").foregroundStyle(Theme.Colors.slate)
            }
            .padding(.vertical, Theme.Spacing.s)
        }
        ForEach(Array(session.orderedCaptureSets.enumerated()), id: \.element.id) { index, set in
            NavigationLink { ReviewView(sessionID: session.id, setID: set.id) } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(index + 1). \(set.stage.label)").font(.headline)
                        Spacer()
                        Text(set.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.footnote).foregroundStyle(Theme.Colors.slate)
                    }
                    Text(set.positioning.summary).font(.footnote).foregroundStyle(Theme.Colors.slate)
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(ViewAngle.allCases) { angle in
                            Thumbnail(image: set.captures[angle].flatMap { store.image(for: $0, in: session) },
                                      label: angle.displayName,
                                      flagged: set.captures[angle].map { !($0.quality?.passed ?? true) } ?? false,
                                      hasLandmarks: set.captures[angle]?.landmarks != nil)
                        }
                    }
                    if !set.isComplete {
                        Button {
                            onCaptureMissing(set, set.missingAngles)
                        } label: {
                            Label("Capture missing: \(set.missingAngles.map(\.displayName).joined(separator: ", "))", systemImage: "camera.badge.ellipsis")
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.caution)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    struct Thumbnail: View {
        let image: UIImage?
        let label: String
        let flagged: Bool
        let hasLandmarks: Bool

        var body: some View {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Theme.Colors.hairline
                        }
                    }
                    .frame(width: 64, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    if flagged {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(Theme.Colors.caution).padding(3)
                    }
                    if hasLandmarks {
                        Image(systemName: "scope")
                            .font(.caption2).foregroundStyle(Theme.Colors.accent).padding(3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .frame(width: 64, height: 84)
                Text(label).font(.caption2).foregroundStyle(Theme.Colors.slate).lineLimit(1)
            }
        }
    }
}
