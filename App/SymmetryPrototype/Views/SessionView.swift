import SwiftUI
import SymmetryCore
import SymmetryModels

/// One session: its capture-set timeline and the actions that start from it.
struct SessionView: View {
    @EnvironmentObject private var store: SessionStore
    let sessionID: UUID

    @State private var showingNewSet = false
    @State private var captureTarget: CaptureTarget?

    struct CaptureTarget: Identifiable {
        let id = UUID()
        let set: CaptureSet
        let angles: [ViewAngle]
    }

    private var session: StudySession? { store.session(id: sessionID) }
    /// A new set is allowed only when every existing set has all three views.
    private var hasIncompleteSet: Bool { session?.captureSets.contains { !$0.isComplete } ?? false }

    var body: some View {
        if let session {
            List {
                Section {
                    TimelineView(session: session) { set, angles in
                        captureTarget = CaptureTarget(set: set, angles: angles)
                    }
                } header: { Text("Capture sets") }

                Section {
                    NavigationLink { ComparisonView(sessionID: sessionID) } label: {
                        Label("Compare capture sets", systemImage: "rectangle.split.2x1")
                    }
                    .disabled(session.captureSets.filter { $0.frontal != nil }.count < 2)
                    NavigationLink { ExportView(sessionID: sessionID) } label: {
                        Label("Export research report", systemImage: "square.and.arrow.up")
                    }
                    .disabled(session.captureSets.isEmpty)
                }

                Section { ResearchNoticeBanner() }
            }
            .navigationTitle(session.studyID)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.xs) {
                    if hasIncompleteSet {
                        Text("Finish or delete the incomplete set before starting a new one.")
                            .font(.footnote).foregroundStyle(Theme.Colors.caution)
                    }
                    Button { showingNewSet = true } label: { Label("New capture set", systemImage: "camera") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(hasIncompleteSet)
                }
                .padding(Theme.Spacing.m)
                .background(.bar)
            }
            .sheet(isPresented: $showingNewSet) {
                NewCaptureSetView { set in
                    showingNewSet = false
                    captureTarget = CaptureTarget(set: set, angles: ViewAngle.allCases)
                }
            }
            .fullScreenCover(item: $captureTarget) { target in
                CaptureView(sessionID: sessionID, captureSet: target.set, anglesToCapture: target.angles)
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
        }
    }
}

/// Stage and positioning for a new capture set.
struct NewCaptureSetView: View {
    @Environment(\.dismiss) private var dismiss
    let onStart: (CaptureSet) -> Void

    @State private var stageChoice: Int = 0
    @State private var customStage = ""
    @State private var positioning = Positioning()

    private var stage: OperativeStage {
        stageChoice < OperativeStage.presets.count ? OperativeStage.presets[stageChoice] : .custom(customStage.trimmingCharacters(in: .whitespaces))
    }
    private var canStart: Bool {
        if case .custom(let text) = stage { return !text.isEmpty }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Operative stage") {
                    Picker("Stage", selection: $stageChoice) {
                        ForEach(Array(OperativeStage.presets.enumerated()), id: \.offset) { i, s in Text(s.label).tag(i) }
                        Text("Other").tag(OperativeStage.presets.count)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if stageChoice == OperativeStage.presets.count {
                        TextField("Describe the stage", text: $customStage)
                    }
                }
                Section {
                    TextField("Table angle, for example 30°", text: $positioning.tableAngle)
                    TextField("Arm position, for example 90° abduction", text: $positioning.armPosition)
                    TextField("Lighting, for example overhead lights only", text: $positioning.lighting)
                    TextField("Note", text: $positioning.note)
                } header: { Text("Positioning") } footer: {
                    Text("Record the same positioning for every set in a session. Comparisons across different positioning are not meaningful.")
                }
            }
            .navigationTitle("New capture set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Start capture") { onStart(CaptureSet(stage: stage, positioning: positioning)) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canStart)
                    .padding(Theme.Spacing.m)
                    .background(.bar)
            }
        }
    }
}
