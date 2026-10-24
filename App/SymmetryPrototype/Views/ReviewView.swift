import SwiftUI
import SymmetryCore
import SymmetryModels

/// Inspect each view of a capture set, fix labels, retake, and open the landmark editor.
struct ReviewView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    let setID: UUID

    @State private var retakeAngle: ViewAngle?
    @State private var confirmDelete = false

    private var session: StudySession? { store.session(id: sessionID) }
    private var set: CaptureSet? { session?.captureSet(id: setID) }

    var body: some View {
        if let session, let set {
            List {
                Section {
                    Text(set.stage.label).font(.headline)
                    Text(set.positioning.summary).font(.footnote).foregroundStyle(Theme.Colors.slate)
                }
                ForEach(ViewAngle.allCases) { angle in
                    Section(angle.displayName) {
                        if let capture = set.captures[angle] {
                            NavigationLink {
                                LandmarkEditorView(sessionID: sessionID, setID: setID, captureID: capture.id)
                            } label: {
                                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                                    if let image = store.image(for: capture, in: session) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(width: 96, height: 128).clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        QualityFailureList(report: capture.quality, overridden: capture.qualityOverridden)
                                        if let lm = capture.landmarks {
                                            Text(lm.isComplete ? "Landmarks placed" : "\(lm.missing.count) landmarks missing")
                                                .font(.footnote).foregroundStyle(Theme.Colors.accent)
                                        } else {
                                            Text(angle == .frontal ? "Place landmarks" : "Optional landmarks")
                                                .font(.footnote).foregroundStyle(Theme.Colors.accent)
                                        }
                                    }
                                }
                            }
                            Button { retakeAngle = angle } label: { Label("Retake this view", systemImage: "camera") }
                        } else {
                            Button { retakeAngle = angle } label: { Label("Capture this view", systemImage: "camera.badge.ellipsis") }
                                .foregroundStyle(Theme.Colors.caution)
                        }
                    }
                }
                Section {
                    Button { swapObliques(set, in: session) } label: {
                        Label("Swap left and right oblique labels", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(set.captures[.leftOblique] == nil && set.captures[.rightOblique] == nil)
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete this capture set", systemImage: "trash") }
                }
                Section { ResearchNoticeBanner() }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $retakeAngle) { angle in
                CaptureView(sessionID: sessionID, captureSet: set, anglesToCapture: [angle])
            }
            .confirmationDialog("Delete this capture set and its three images?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete capture set", role: .destructive) { delete(set, in: session) }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("Capture set not found", systemImage: "questionmark.folder")
        }
    }

    private func swapObliques(_ set: CaptureSet, in session: StudySession) {
        var s = session
        var updated = set
        updated.swapObliqueLabels()
        s.update(updated)
        store.save(s)
    }

    private func delete(_ set: CaptureSet, in session: StudySession) {
        var s = session
        s.captureSets.removeAll { $0.id == set.id }
        guard store.save(s) else { return }
        for capture in set.orderedCaptures { store.deleteImage(for: capture, in: session) }
        dismiss()
    }
}

