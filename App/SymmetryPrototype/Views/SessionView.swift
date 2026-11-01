import SwiftUI
import SymmetryCore
import SymmetryModels

/// Where the session screen can go next. One `navigationDestination(item:)` renders them all.
enum SessionRoute: Hashable, Identifiable {
    case markPoints(setID: UUID, captureID: UUID)
    case compare(earlierID: UUID?, laterID: UUID?)
    case export
    case review(setID: UUID)

    var id: Self { self }
}

/// Screen 3, the wizard: four steps, the photo sets, and exactly one next action.
/// Every state shown here comes from `SessionProgress`; nothing is computed twice.
struct SessionView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sessionID: UUID

    @State private var route: SessionRoute?
    @State private var hasCompared = false
    @State private var confirmDelete = false
    @State private var showingNewSet = false
    @State private var newSetContext: NewSetContext?
    @State private var pendingSet: CaptureSet?
    @State private var captureTarget: CaptureTarget?

    /// What the New photo set sheet is pre-filled with.
    struct NewSetContext {
        let suggestedStage: OperativeStage
        let previousStage: OperativeStage?
        let previousPositioning: Positioning?
        let previousSetIndex: Int?
    }

    struct CaptureTarget: Identifiable {
        let id = UUID()
        let set: CaptureSet
        /// 1-based position of the set in the session, shown in the camera header.
        let index: Int
        let angles: [ViewAngle]
    }

    private var session: StudySession? { store.session(id: sessionID) }

    var body: some View {
        if let session {
            let progress = SessionProgress(session: session, settings: settings.reportSettings, hasCompared: hasCompared)
            let sets = session.orderedCaptureSets
            let nextIsExport: Bool = { if case .export = progress.next { return true } else { return false } }()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Started \(session.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.slate)

                    StepListView(progress: progress) { step in
                        tap(step, progress: progress, session: session)
                    }
                    .cardStyle()

                    if let incomplete = progress.firstIncomplete {
                        let missing = incomplete.set.missingAngles.count
                        GuidanceCard(kind: .caution,
                                     body: "Set \(incomplete.index) is missing \(missing) photo\(missing == 1 ? "" : "s"). Finish it or delete it before starting another set.") {
                            Button(missing == 1 ? "Take the missing photo" : "Take the missing photos") {
                                perform(progress.next)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }

                    Text("Photo sets")
                        .font(.stepTitle)
                        .foregroundStyle(Theme.Colors.ink)

                    if sets.isEmpty {
                        Text("No photo sets yet. Tap the button below to take the first three photos.")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .cardStyle()
                    } else {
                        TimelineView(session: session,
                                     sigma: settings.landmarkSigmaRatio,
                                     onCaptureMissing: { set, index, angles in
                                         captureTarget = CaptureTarget(set: set, index: index, angles: angles)
                                     },
                                     onMarkPoints: { set, _, capture in
                                         route = .markPoints(setID: set.id, captureID: capture.id)
                                     })
                    }

                    if progress.firstIncomplete == nil && !sets.isEmpty {
                        Button("Add a photo set at another stage") {
                            presentNewSet(after: sets.last, index: sets.count)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    // The bottom bar drops its detail line at accessibility text sizes (it cannot
                    // scroll), so the same sentence is shown here where it can.
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(progress.next.detail)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    deleteCard
                    ResearchNoticeBanner()
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Colors.paper)
            .navigationTitle(session.studyID)
            .confirmationDialog("Delete this session and all of its images?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete session", role: .destructive) { delete(session) }
                Button("Cancel", role: .cancel) {}
            }
            .navigationDestination(item: $route) { route in
                destination(for: route)
            }
            .safeAreaInset(edge: .bottom) {
                NextActionBar(title: progress.next.title,
                              detail: progress.next.detail,
                              secondaryTitle: nextIsExport ? "Compare again" : nil,
                              secondaryAction: nextIsExport ? { route = .compare(earlierID: nil, laterID: nil) } : nil) {
                    perform(progress.next)
                }
            }
            .onAppear { hasCompared = ComparedFlag.isSet(sessionID: sessionID) }
            .task(id: route) { hasCompared = ComparedFlag.isSet(sessionID: sessionID) }
            .sheet(isPresented: $showingNewSet, onDismiss: {
                // Present the camera only after the sheet has fully dismissed.
                if let set = pendingSet {
                    pendingSet = nil
                    let index = (store.session(id: sessionID)?.orderedCaptureSets.count ?? 0) + 1
                    captureTarget = CaptureTarget(set: set, index: index, angles: ViewAngle.allCases)
                }
            }) {
                let context = newSetContext ?? NewSetContext(suggestedStage: OperativeStage.presets[0],
                                                             previousStage: nil,
                                                             previousPositioning: nil,
                                                             previousSetIndex: nil)
                NewCaptureSetView(suggestedStage: context.suggestedStage,
                                  previousPositioning: context.previousPositioning,
                                  previousSetIndex: context.previousSetIndex,
                                  previousStage: context.previousStage) { set in
                    pendingSet = set
                    showingNewSet = false
                }
            }
            .fullScreenCover(item: $captureTarget) { target in
                CaptureView(sessionID: sessionID, captureSet: target.set, setIndex: target.index, anglesToCapture: target.angles)
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
        }
    }

    /// The visible way to remove one session. The Sessions list keeps its long press as a shortcut.
    private var deleteCard: some View {
        Button("Delete this session") { confirmDelete = true }
            .buttonStyle(PrimaryButtonStyle(isDestructive: true))
            .cardStyle()
    }

    /// Deletes the session and returns to the Sessions list. On a storage failure the
    /// store keeps the session and reports the problem, so this screen stays put.
    private func delete(_ session: StudySession) {
        store.delete(session)
        if store.session(id: sessionID) == nil { dismiss() }
    }

    // MARK: - Navigation

    @ViewBuilder
    private func destination(for route: SessionRoute) -> some View {
        switch route {
        case .markPoints(let setID, let captureID):
            LandmarkEditorView(sessionID: sessionID, setID: setID, captureID: captureID)
        case .compare(let earlierID, let laterID):
            ComparisonView(sessionID: sessionID, earlierID: earlierID, laterID: laterID)
        case .export:
            ExportView(sessionID: sessionID)
        case .review(let setID):
            ReviewView(sessionID: sessionID, setID: setID)
        }
    }

    /// Carries out the one next action the wizard computed.
    private func perform(_ action: SessionProgress.NextAction) {
        switch action {
        case .newSet(let suggestedStage, let previousPositioning, let previousSetIndex, _, _):
            let previous = previousSetIndex.flatMap { index -> CaptureSet? in
                let ordered = session?.orderedCaptureSets ?? []
                return ordered.indices.contains(index - 1) ? ordered[index - 1] : nil
            }
            newSetContext = NewSetContext(suggestedStage: suggestedStage,
                                          previousStage: previous?.stage,
                                          previousPositioning: previousPositioning,
                                          previousSetIndex: previousSetIndex)
            showingNewSet = true
        case .captureMissing(let set, let index, let angles, _, _):
            captureTarget = CaptureTarget(set: set, index: index, angles: angles)
        case .markPoints(let set, _, let capture, _, _):
            route = .markPoints(setID: set.id, captureID: capture.id)
        case .compare(let earlier, _, let later, _, _, _):
            route = .compare(earlierID: earlier.id, laterID: later.id)
        case .export:
            route = .export
        }
    }

    /// Opens the New photo set sheet pre-filled from the last set (or empty for the first).
    private func presentNewSet(after last: CaptureSet?, index: Int) {
        newSetContext = NewSetContext(suggestedStage: SessionProgress.suggestedStage(after: last?.stage),
                                      previousStage: last?.stage,
                                      previousPositioning: last?.positioning,
                                      previousSetIndex: last == nil ? nil : index)
        showingNewSet = true
    }

    /// A tapped step performs that step's action. StepListView only wires taps for
    /// actionable steps, so an upcoming row never reaches here.
    private func tap(_ step: SessionProgress.Step, progress: SessionProgress, session: StudySession) {
        let ordered = session.orderedCaptureSets
        switch step {
        case .takePhotos:
            if progress.next.step == .takePhotos {
                perform(progress.next)
            } else {
                presentNewSet(after: ordered.last, index: ordered.count)
            }
        case .markPoints:
            if case .markPoints = progress.next {
                perform(progress.next)
            } else if let unmarked = ordered.first(where: { $0.frontal != nil && $0.frontal?.landmarks?.isComplete != true }),
                      let frontal = unmarked.frontal {
                route = .markPoints(setID: unmarked.id, captureID: frontal.id)
            } else if let first = ordered.first(where: { $0.frontal != nil }), let frontal = first.frontal {
                route = .markPoints(setID: first.id, captureID: frontal.id)
            }
        case .compare:
            if case .compare(let earlier, _, let later, _, _, _) = progress.next {
                route = .compare(earlierID: earlier.id, laterID: later.id)
            } else {
                route = .compare(earlierID: progress.measuredSets.first?.id, laterID: progress.measuredSets.last?.id)
            }
        case .export:
            route = .export
        }
    }
}

/// Screen 4: stage and positioning for a new photo set, pre-filled from the previous set.
struct NewCaptureSetView: View {
    @Environment(\.dismiss) private var dismiss
    let suggestedStage: OperativeStage
    let previousPositioning: Positioning?
    let previousSetIndex: Int?
    /// The previous set's stage, named in "Suggested because the last set was …".
    let previousStage: OperativeStage?
    let onStart: (CaptureSet) -> Void

    @State private var stageChoice: Int
    @State private var customStage: String
    @State private var positioning: Positioning
    /// Row index that carries the "Suggested" badge.
    private let suggestedChoice: Int

    init(suggestedStage: OperativeStage,
         previousPositioning: Positioning?,
         previousSetIndex: Int?,
         onStart: @escaping (CaptureSet) -> Void) {
        self.init(suggestedStage: suggestedStage,
                  previousPositioning: previousPositioning,
                  previousSetIndex: previousSetIndex,
                  previousStage: nil,
                  onStart: onStart)
    }

    init(suggestedStage: OperativeStage,
         previousPositioning: Positioning?,
         previousSetIndex: Int?,
         previousStage: OperativeStage?,
         onStart: @escaping (CaptureSet) -> Void) {
        self.suggestedStage = suggestedStage
        self.previousPositioning = previousPositioning
        self.previousSetIndex = previousSetIndex
        self.previousStage = previousStage
        self.onStart = onStart

        let presets = OperativeStage.presets
        let choice: Int
        let custom: String
        if let i = presets.firstIndex(of: suggestedStage) {
            choice = i
            custom = ""
        } else if case .custom(let text) = suggestedStage {
            choice = presets.count
            custom = text
        } else {
            choice = 0
            custom = ""
        }
        _stageChoice = State(initialValue: choice)
        _customStage = State(initialValue: custom)
        _positioning = State(initialValue: previousPositioning ?? Positioning())
        suggestedChoice = choice
    }

    private var otherChoice: Int { OperativeStage.presets.count }

    private var stage: OperativeStage {
        stageChoice < otherChoice
            ? OperativeStage.presets[stageChoice]
            : .custom(customStage.trimmingCharacters(in: .whitespaces))
    }

    private var canStart: Bool {
        if case .custom(let text) = stage { return !text.isEmpty }
        return true
    }

    /// Label for the "Suggested because…" line. Falls back to the preset before the
    /// suggestion when the caller did not pass the previous stage.
    private var previousStageLabel: String? {
        if let previousStage { return previousStage.label }
        guard previousSetIndex != nil else { return nil }
        if suggestedChoice == otherChoice { return suggestedStage.label }
        return OperativeStage.presets[max(suggestedChoice - 1, 0)].label
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    GuidanceCard(kind: .info,
                                 body: "You will take 3 photos in a fixed order: Frontal, Left oblique, Right oblique. The app guides each one.")

                    Text("Stage of the operation")
                        .font(.stepTitle)
                        .foregroundStyle(Theme.Colors.ink)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(OperativeStage.presets.enumerated()), id: \.offset) { i, preset in
                            stageRow(label: preset.label, index: i)
                            Divider().overlay(Theme.Colors.hairline)
                        }
                        stageRow(label: "Other", index: otherChoice)
                        if stageChoice == otherChoice {
                            TextField("Describe the stage", text: $customStage)
                                .font(.body)
                                .fieldStyle()
                                .padding(.top, Theme.Spacing.s)
                        }
                    }
                    .cardStyle()

                    if previousSetIndex != nil, let previousStageLabel {
                        Text("Suggested because the last set was \(previousStageLabel).")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.slate)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Positioning (optional, but keep it the same every time)")
                        .font(.stepTitle)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        TextField("Table angle, for example 30°", text: $positioning.tableAngle)
                            .font(.body)
                            .fieldStyle()
                        TextField("Arm position, for example 90° abduction", text: $positioning.armPosition)
                            .font(.body)
                            .fieldStyle()
                        TextField("Lighting, for example overhead lights only", text: $positioning.lighting)
                            .font(.body)
                            .fieldStyle()
                        TextField("Note", text: $positioning.note)
                            .font(.body)
                            .fieldStyle()
                        if let previousSetIndex {
                            Text("Copied from set \(previousSetIndex). Change only if the patient or the lighting moved.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.slate)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Colors.paper)
            .navigationTitle("New photo set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.s) {
                    Button("Start the camera") { onStart(CaptureSet(stage: stage, positioning: positioning)) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canStart)
                        .opacity(canStart ? 1 : 0.5)
                    if !canStart {
                        Text("Describe the stage first")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.caution)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Theme.Spacing.m)
                .background(.bar)
            }
        }
    }

    /// A 56pt radio row: circle or filled tick, the label, and the "Suggested" badge.
    private func stageRow(label: String, index: Int) -> some View {
        let selected = stageChoice == index
        return Button {
            stageChoice = index
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.Colors.accent : Theme.Colors.slate)
                Text(label)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if index == suggestedChoice {
                    Text("Suggested")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xs)
                        .overlay(Capsule().stroke(Theme.Colors.accent, lineWidth: 1))
                }
            }
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
