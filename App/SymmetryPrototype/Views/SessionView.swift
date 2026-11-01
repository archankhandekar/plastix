import SwiftUI
import SymmetryCore
import SymmetryModels

/// Session home, for a study session or the virtual patient. Symmetry first: the focus
/// set's turned frontal photo and its left-right gauges come before the list of sets.
/// Every state shown here comes from `SessionWizard`, `SetStatus` and `SetReading`; screens
/// are opened by appending `AppRoute` values to the navigator.
struct SessionView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var stores: SessionStores
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.sessionKind) private var kind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sessionID: UUID

    @State private var confirmDelete = false
    @State private var showingNewSet = false
    @State private var newSetContext: NewSetContext?
    @State private var pendingSet: CaptureSet?
    @State private var captureTarget: CaptureTarget?
    @State private var practiceError: String?
    /// Bumped on appear so the wizard re-reads the UI-only flags after a pushed screen set one.
    @State private var flagsRevision = 0

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

    init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    private var session: StudySession? { store.session(id: sessionID) }
    private var ref: SessionRef { SessionRef(id: sessionID, kind: kind) }
    private var isPractice: Bool { kind == .practice }
    private var sigma: Double { settings.landmarkSigmaRatio }

    var body: some View {
        if let session {
            let _ = flagsRevision
            let wizard = SessionWizard(session: session, settings: settings.reportSettings, kind: kind)
            content(session: session, wizard: wizard)
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
                .practiceBand(isPractice)
        }
    }

    private func content(session: StudySession, wizard: SessionWizard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if isPractice {
                    PracticeTourSection(tour: PracticeTour(session: session, sigma: sigma),
                                        onSelect: { task in performTour(task, session: session, wizard: wizard) },
                                        onReset: resetPractice)
                }

                StepRail(items: stepItems(wizard), compact: true) { id in
                    if let step = SessionWizard.Step(rawValue: id) {
                        tap(step, wizard: wizard, session: session)
                    }
                }

                if let focus = wizard.focusSet {
                    focusSection(focus.set, index: focus.index, session: session)
                } else {
                    Text("No photo sets yet. Tap the button below to take the first three photos.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                stagesSection(session: session)

                if !session.orderedCaptureSets.isEmpty {
                    allSetsSection(session: session, wizard: wizard)
                }

                // The bottom bar drops its detail line at accessibility text sizes (it cannot
                // scroll), so the same sentence is shown here where it can.
                if dynamicTypeSize.isAccessibilitySize {
                    Text(wizard.next.detail)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !isPractice {
                    Button("Delete this session") { confirmDelete = true }
                        .buttonStyle(PrimaryButtonStyle(isDestructive: true))
                }

                ResearchNoticeBanner()
            }
            .padding(.horizontal, Theme.Spacing.margin)
            .padding(.vertical, Theme.Spacing.l)
        }
        .background(Theme.Colors.tray)
        .practiceBand(isPractice)
        .navigationTitle(isPractice ? "Virtual patient" : session.studyID)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            NextActionBar(title: wizard.next.title, detail: wizard.next.detail) {
                perform(wizard.next, session: session)
            }
        }
        .confirmationDialog("Delete this session and all of its images?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) { delete(session) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("The virtual patient could not be started", isPresented: .init(get: { practiceError != nil }, set: { if !$0 { practiceError = nil } })) {
            Button("OK") { practiceError = nil }
        } message: { Text(practiceError ?? "") }
        .onAppear {
            flagsRevision += 1
            performNextIfRequested()
        }
        .onChange(of: navigator.performNextOnHome) { performNextIfRequested() }
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
            .sessionScope(kind)
        }
        .fullScreenCover(item: $captureTarget, onDismiss: { flagsRevision += 1 }) { target in
            CaptureView(sessionID: sessionID, captureSet: target.set, setIndex: target.index, anglesToCapture: target.angles)
                .sessionScope(kind)
        }
    }

    // MARK: - Sections

    /// The focus set: its title, when it was taken, its turned frontal photo and its four
    /// left-right readings.
    @ViewBuilder
    private func focusSection(_ set: CaptureSet, index: Int, session: StudySession) -> some View {
        let status = SetStatus(set: set, index: index, sigma: sigma)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(status.title)
                    .font(.screenTitle)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(status.takenLine)
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SetPlateThumbnail(image: set.frontal.flatMap { store.image(for: $0, in: session) },
                              landmarks: set.frontal?.landmarks,
                              setIndex: index,
                              practice: isPractice) {
                navigator.push(.symmetry(ref, setID: set.id))
            }

        }

        if let frontal = set.frontal {
            gaugesSection(set: set, frontal: frontal)
        }
    }

    /// "Left and right in this set": three compact lean gauges and the overlap line. Each
    /// opens the symmetry result focused on that reading.
    private func gaugesSection(set: CaptureSet, frontal: Capture) -> some View {
        let reading = SetReading(landmarks: frontal.landmarks, sigma: sigma, frontal: frontal)
        let markPoints = { navigator.push(.markPoints(ref, setID: set.id, captureID: frontal.id)) }
        let hasAnyPoint = frontal.landmarks.map { !$0.points.isEmpty } ?? false
        return VStack(alignment: .leading, spacing: Theme.Spacing.gaugeGap) {
            Text("Left and right in this set")
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
                .accessibilityAddTraits(.isHeader)

            if hasAnyPoint {
                ForEach([BilateralMetric.nippleHeight, .nippleMidline, .foldHeight]) { metric in
                    let r = reading.reading(metric)
                    LeanGauge(title: metric.title,
                              measurement: r.measurement,
                              patientRightEnd: metric.patientRightEnd ?? "",
                              patientLeftEnd: metric.patientLeftEnd ?? "",
                              sentence: r.sentence,
                              exportName: metric.exportName,
                              notMeasuredReason: r.notMeasuredReason,
                              compact: true,
                              onSelect: { navigator.push(.symmetry(ref, setID: set.id, focus: metric.layer)) },
                              onMarkPoints: markPoints)
                }
                let overlap = reading.reading(.outlineOverlap)
                OverlapScale(measurement: overlap.measurement,
                             sentence: overlap.sentence,
                             exportName: BilateralMetric.outlineOverlap.exportName,
                             notMeasuredReason: overlap.notMeasuredReason,
                             compact: true,
                             onSelect: { navigator.push(.symmetry(ref, setID: set.id, focus: BilateralMetric.outlineOverlap.layer)) },
                             onMarkPoints: markPoints)
            } else {
                // No point placed yet: one reason instead of four identical ones.
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
                    Button("Mark points", action: markPoints)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    /// Only once two or more sets are measured: each reading across the sets, compact.
    @ViewBuilder
    private func stagesSection(session: StudySession) -> some View {
        let series = StageSeries(session: session, sigma: sigma)
        if series.measuredCount >= 2 {
            VStack(alignment: .leading, spacing: Theme.Spacing.gaugeGap) {
                Text("How each left-right difference changed across stages")
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ForEach(BilateralMetric.allCases) { metric in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(metric.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.Colors.ink)
                        StageLeanChart(kind: chartKind(metric),
                                       rows: series.rows(for: metric).map {
                                           StageLeanChart.Row(id: $0.id, label: $0.label, measurement: $0.measurement)
                                       },
                                       compact: true)
                    }
                    .accessibilityElement(children: .contain)
                }
                Button("See across stages") { navigator.push(.acrossStages(ref)) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func allSetsSection(session: StudySession, wizard: SessionWizard) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("All sets")
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            AllSetsList(session: session, sigma: sigma) { set, status in
                navigator.push(status.isMeasured ? .symmetry(ref, setID: set.id) : .review(ref, setID: set.id))
            }
            if let incomplete = wizard.firstIncomplete {
                incompleteCaution(incomplete.set, index: incomplete.index)
                    .padding(.top, Theme.Spacing.m)
            } else {
                Button("Add a photo set at another stage") {
                    let ordered = session.orderedCaptureSets
                    presentNewSet(after: ordered.last, index: ordered.count)
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Theme.Spacing.m)
            }
        }
    }

    /// "Set N is missing 1 photo. Finish it or delete it before starting another set."
    private func incompleteCaution(_ set: CaptureSet, index: Int) -> some View {
        let missing = set.missingAngles
        let sentence = missing.count == 1
            ? "Set \(index) is missing 1 photo. Finish it or delete it before starting another set."
            : "Set \(index) is missing \(missing.count) photos. Finish it or delete it before starting another set."
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
                Text(sentence)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.body)
            .foregroundStyle(Theme.Colors.caution)
            .accessibilityElement(children: .combine)
            Button(missing.count == 1 ? "Take the missing photo" : "Take the missing photos") {
                captureTarget = CaptureTarget(set: set, index: index, angles: missing)
            }
            .buttonStyle(SecondaryButtonStyle())
            Button("Open the photos of set \(index)") { navigator.push(.review(ref, setID: set.id)) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func chartKind(_ metric: BilateralMetric) -> StageLeanChart.Kind {
        if let right = metric.patientRightEnd, let left = metric.patientLeftEnd {
            return .difference(patientRightEnd: right, patientLeftEnd: left)
        }
        return .overlap
    }

    private func stepItems(_ wizard: SessionWizard) -> [StepRail.Item] {
        SessionWizard.Step.allCases.map { step in
            let state = wizard.states[step] ?? .upcoming("")
            let railState: StepRail.State
            switch state {
            case .done: railState = .done
            case .current: railState = .current
            case .upcoming: railState = .upcoming
            }
            return StepRail.Item(id: step.rawValue, number: step.rawValue, title: step.title,
                                 status: state.status, state: railState,
                                 isActionable: wizard.isActionable(step))
        }
    }

    // MARK: - Actions

    /// Carries out the one next action the wizard computed. Taking photos is handled here;
    /// everything else is a route.
    private func perform(_ action: SessionWizard.Action, session: StudySession) {
        switch action {
        case .newSet(let suggestedStage, let previousPositioning, let previousSetIndex, _, _):
            let ordered = session.orderedCaptureSets
            let previous = previousSetIndex.flatMap { index -> CaptureSet? in
                ordered.indices.contains(index - 1) ? ordered[index - 1] : nil
            }
            newSetContext = NewSetContext(suggestedStage: suggestedStage,
                                          previousStage: previous?.stage,
                                          previousPositioning: previousPositioning,
                                          previousSetIndex: previousSetIndex)
            showingNewSet = true
        case .captureMissing(let set, let index, let angles, _, _):
            captureTarget = CaptureTarget(set: set, index: index, angles: angles)
        default:
            if let route = action.route(ref) { navigator.push(route) }
        }
    }

    /// Opens the New photo set sheet pre-filled from the last set (or empty for the first).
    private func presentNewSet(after last: CaptureSet?, index: Int) {
        newSetContext = NewSetContext(suggestedStage: SessionWizard.suggestedStage(after: last?.stage),
                                      previousStage: last?.stage,
                                      previousPositioning: last?.positioning,
                                      previousSetIndex: last == nil ? nil : index)
        showingNewSet = true
    }

    /// A tapped step performs that step's action. The rail only wires taps for actionable
    /// steps, so an upcoming step that cannot act never reaches here.
    private func tap(_ step: SessionWizard.Step, wizard: SessionWizard, session: StudySession) {
        let ordered = session.orderedCaptureSets
        if wizard.next.step == step {
            perform(wizard.next, session: session)
            return
        }
        switch step {
        case .takePhotos:
            if let incomplete = wizard.firstIncomplete {
                captureTarget = CaptureTarget(set: incomplete.set, index: incomplete.index, angles: incomplete.set.missingAngles)
            } else {
                presentNewSet(after: ordered.last, index: ordered.count)
            }
        case .markPoints:
            let unmarked = ordered.first { $0.frontal != nil && $0.frontal?.landmarks?.isComplete != true }
            if let set = unmarked ?? ordered.first(where: { $0.frontal != nil }), let frontal = set.frontal {
                navigator.push(.markPoints(ref, setID: set.id, captureID: frontal.id))
            }
        case .seeSides:
            if let focus = wizard.measuredIndexed.last {
                navigator.push(.symmetry(ref, setID: focus.set.id))
            }
        case .export:
            navigator.push(.export(ref))
        }
    }

    /// Opens one task of the practice tour. When the task's set does not exist (the
    /// session was changed by hand), the wizard's next action runs instead.
    private func performTour(_ task: PracticeTourTask, session: StudySession, wizard: SessionWizard) {
        let sets = session.orderedCaptureSets
        func set(_ n: Int) -> CaptureSet? { sets.count >= n ? sets[n - 1] : nil }
        switch task {
        case .readSet1:
            if let s = set(1) { navigator.push(.symmetry(ref, setID: s.id)); return }
        case .lookAtObliques:
            if let s = set(1) { navigator.push(.symmetry(ref, setID: s.id, tab: .obliques)); return }
        case .markSet3:
            if let s = set(3), let frontal = s.frontal {
                navigator.push(.markPoints(ref, setID: s.id, captureID: frontal.id))
                return
            }
        case .takeSet4:
            if let incomplete = wizard.firstIncomplete {
                captureTarget = CaptureTarget(set: incomplete.set, index: incomplete.index, angles: incomplete.set.missingAngles)
                return
            }
            if let s = set(4) {
                let measured = SessionWizard.isMeasured(s, sigma: sigma)
                navigator.push(measured ? .symmetry(ref, setID: s.id) : .review(ref, setID: s.id))
                return
            }
            presentNewSet(after: sets.last, index: sets.count)
            return
        case .acrossStages:
            navigator.push(.acrossStages(ref))
            return
        }
        perform(wizard.next, session: session)
    }

    /// Performs the next action once, when a screen popped back here asking for it.
    private func performNextIfRequested() {
        guard navigator.performNextOnHome else { return }
        navigator.performNextOnHome = false
        guard let session else { return }
        let wizard = SessionWizard(session: session, settings: settings.reportSettings, kind: kind)
        let action = wizard.next
        // Let the pop finish before a sheet or the camera is presented.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            perform(action, session: session)
        }
    }

    /// Starts the virtual patient again and replaces this home with the new session's.
    private func resetPractice() {
        do {
            let fresh = try stores.practice.reset()
            navigator.popToSession(SessionRef(id: fresh.id, kind: .practice))
        } catch {
            practiceError = stores.practice.store.lastError ?? "Its photos could not be prepared on this phone."
        }
    }

    /// Deletes the session and returns to Sessions. On a storage failure the store keeps the
    /// session and reports the problem, so this screen stays put.
    private func delete(_ session: StudySession) {
        UIFlags.clear(session: session)
        store.delete(session)
        if store.session(id: sessionID) == nil { navigator.popToRoot() }
    }
}

/// New photo set: stage and positioning, pre-filled from the previous set. Flat 56pt radio
/// rows with a Drape check; one primary action at the bottom.
struct NewCaptureSetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sessionKind) private var kind
    let suggestedStage: OperativeStage
    let previousPositioning: Positioning?
    let previousSetIndex: Int?
    /// The previous set's stage, named in "Suggested because the last set was ...".
    let previousStage: OperativeStage?
    let onStart: (CaptureSet) -> Void

    @State private var stageChoice: Int
    @State private var customStage: String
    @State private var positioning: Positioning
    /// Row index that carries the "Suggested" note.
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

    /// Label for the "Suggested because ..." line. Falls back to the preset before the
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
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    Text("You will take 3 photos in a fixed order: Frontal, Left oblique, Right oblique. The app guides each one.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Stage of the operation")
                            .font(.sectionTitle)
                            .foregroundStyle(Theme.Colors.ink)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(OperativeStage.presets.enumerated()), id: \.offset) { i, preset in
                                stageRow(label: preset.label, index: i)
                            }
                            stageRow(label: "Other", index: otherChoice)
                        }
                        if stageChoice == otherChoice {
                            TextField("Describe the stage", text: $customStage)
                                .font(.body)
                                .foregroundStyle(Theme.Colors.ink)
                                .fieldStyle()
                        }
                        if previousSetIndex != nil, let previousStageLabel {
                            Text("Suggested because the last set was \(previousStageLabel).")
                                .font(.support)
                                .foregroundStyle(Theme.Colors.graduation)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Positioning (optional, but keep it the same every time)")
                            .font(.sectionTitle)
                            .foregroundStyle(Theme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        TextField("Table angle, for example 30°", text: $positioning.tableAngle)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fieldStyle()
                        TextField("Arm position, for example 90° abduction", text: $positioning.armPosition)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fieldStyle()
                        TextField("Lighting, for example overhead lights only", text: $positioning.lighting)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fieldStyle()
                        TextField("Note", text: $positioning.note)
                            .font(.body)
                            .foregroundStyle(Theme.Colors.ink)
                            .fieldStyle()
                        if let previousSetIndex {
                            Text("Copied from set \(previousSetIndex). Change only if the patient or the lighting moved.")
                                .font(.support)
                                .foregroundStyle(Theme.Colors.graduation)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.margin)
                .padding(.vertical, Theme.Spacing.l)
            }
            .background(Theme.Colors.tray)
            .practiceBand(kind == .practice)
            .navigationTitle("New photo set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.s) {
                    if !canStart {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                            Image(systemName: "exclamationmark.triangle")
                                .accessibilityHidden(true)
                            Text("Describe the stage first.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.body)
                        .foregroundStyle(Theme.Colors.caution)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Start the camera") { onStart(CaptureSet(stage: stage, positioning: positioning)) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canStart)
                }
                .padding(.horizontal, Theme.Spacing.margin)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.Colors.tray)
            }
        }
    }

    /// A 56pt radio row: an empty ring or a Drape check, the label, and "Suggested".
    private func stageRow(label: String, index: Int) -> some View {
        let selected = stageChoice == index
        return Button {
            stageChoice = index
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Theme.Colors.drape : Theme.Colors.graduation,
                                      lineWidth: selected ? 2 : 1.5)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.Colors.drape)
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if index == suggestedChoice {
                        Text("Suggested")
                            .font(.support)
                            .foregroundStyle(Theme.Colors.drape)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: Theme.tapTarget, alignment: .leading)
            .background(selected ? Theme.Colors.fieldWash : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
