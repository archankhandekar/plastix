import SwiftUI
import SymmetryModels

/// Sessions, the root screen: every study session as a flat row with its study code and the
/// one thing to do next, then the virtual patient in its own hatched Practice section.
/// Rows navigate by appending `AppRoute` values to the app's navigator.
///
/// Call it as `SessionListView()` under a root that injects `SessionStores`, `AppNavigator`
/// and `AppSettings`. The `path` parameter is not used for navigation. It only exists for the
/// pre-navigator root, which passes a `NavigationPath` and injects none of the new objects:
/// in that case the list hosts its own stores and navigator so the app (and the unit-test
/// host) still launches. Never pass a path from a root that injects `SessionStores`.
struct SessionListView: View {
    private let hostsLegacyEnvironment: Bool

    init(path: Binding<NavigationPath>? = nil) {
        hostsLegacyEnvironment = path != nil
    }

    var body: some View {
        if hostsLegacyEnvironment {
            LegacyEnvironmentHost { SessionListContent() }
        } else {
            SessionListContent()
        }
    }
}

/// Supplies `SessionStores` and `AppNavigator` for the pre-navigator root only.
private struct LegacyEnvironmentHost<Content: View>: View {
    @StateObject private var stores = SessionStores(study: SessionStore(), practice: PracticeStore())
    @StateObject private var navigator = AppNavigator()
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environmentObject(stores)
            .environmentObject(navigator)
    }
}

private struct SessionListContent: View {
    @EnvironmentObject private var stores: SessionStores
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var settings: AppSettings

    @State private var showingNewSession = false
    @State private var pendingDelete: StudySession?
    /// Set by the New study session sheet; pushed once the sheet has fully dismissed.
    @State private var pendingPush: UUID?
    @State private var confirmPracticeReset = false
    @State private var practiceError: String?

    private var study: SessionStore { stores.study }
    private var practice: PracticeStore { stores.practice }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                studySection
                practiceSection
                Text("Research prototype. Not a medical device.")
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.Spacing.margin)
            .padding(.vertical, Theme.Spacing.l)
        }
        .background(Theme.Colors.tray)
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings") { navigator.push(.settings) }
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("New study session") { showingNewSession = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.Spacing.margin)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.Colors.tray)
        }
        .sheet(isPresented: $showingNewSession, onDismiss: {
            if let id = pendingPush {
                pendingPush = nil
                navigator.push(.session(SessionRef(id: id, kind: .study)))
            }
        }) {
            NewSessionSheet(onCreated: { created in pendingPush = created.id })
        }
        .confirmationDialog("Delete this session and all of its images?",
                            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                if let s = pendingDelete {
                    UIFlags.clear(session: s)
                    study.delete(s)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .confirmationDialog("Start the virtual patient again from the beginning?",
                            isPresented: $confirmPracticeReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { resetPractice() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Storage problem", isPresented: .init(get: { study.lastError != nil }, set: { if !$0 { study.lastError = nil } })) {
            Button("OK") { study.lastError = nil }
        } message: { Text(study.lastError ?? "") }
        .alert("The virtual patient could not be started", isPresented: .init(get: { practiceError != nil }, set: { if !$0 { practiceError = nil } })) {
            Button("OK") { practiceError = nil }
        } message: { Text(practiceError ?? "") }
    }

    // MARK: - Study

    @ViewBuilder
    private var studySection: some View {
        if study.sessions.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("No study sessions yet")
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.Colors.ink)
                Text("A session is one patient, identified only by a study code. It holds every set of photos you take for that patient.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(study.sessions) { session in
                    studyRow(session)
                }
            }
        }
    }

    private func studyRow(_ session: StudySession) -> some View {
        let wizard = SessionWizard(session: session, settings: settings.reportSettings, kind: .study)
        return Button {
            navigator.push(.session(SessionRef(id: session.id, kind: .study)))
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(session.studyID)
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.Colors.ink)
                Text(wizard.summaryLine)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Started " + session.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.support)
                    .foregroundStyle(Theme.Colors.graduation)
            }
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) { pendingDelete = session }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Practice

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Practice")
                .font(.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            if practice.isAvailable {
                practiceRow
                if practice.session != nil {
                    Button("Reset the virtual patient") { confirmPracticeReset = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                Text("The virtual patient is not in this build.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A 72pt hatched row. The hatch marks practice data and nothing else; the words sit on a
    /// Tray backing so they stay legible over it.
    private var practiceRow: some View {
        Button(action: openPractice) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(practice.session == nil ? "Try the virtual patient" : "Open the virtual patient")
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Practise the whole app on a 3D mannequin. Nothing is study data.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.tray, in: RoundedRectangle(cornerRadius: Theme.photoRadius))
            .padding(Theme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background {
                ZStack {
                    Theme.Colors.tray
                    HatchPattern(spacing: 6)
                        .stroke(Theme.Colors.graduation.opacity(0.25), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Seeds the virtual patient the first time, then opens its session home.
    private func openPractice() {
        do {
            let session = try practice.session ?? practice.seed()
            navigator.push(.session(SessionRef(id: session.id, kind: .practice)))
        } catch {
            practiceError = practice.store.lastError ?? "Its photos could not be prepared on this phone."
        }
    }

    private func resetPractice() {
        do {
            try practice.reset()
        } catch {
            practiceError = practice.store.lastError ?? "Its photos could not be prepared on this phone."
        }
    }
}

/// New study session: one field for the study code, with the rule beneath it and a live
/// counter. On success the caller receives the new session and the sheet dismisses itself.
struct NewSessionSheet: View {
    @EnvironmentObject private var stores: SessionStores
    @Environment(\.dismiss) private var dismiss
    let onCreated: (StudySession) -> Void

    @State private var studyID: String
    /// Once true, the field's validation message is shown and follows each edit.
    @State private var showsValidation: Bool
    /// A storage failure on create, shown instead of the validation message.
    @State private var storageMessage: String?

    init(initialStudyID: String = "", showValidation: Bool = false, onCreated: @escaping (StudySession) -> Void) {
        self.onCreated = onCreated
        _studyID = State(initialValue: initialStudyID)
        _showsValidation = State(initialValue: showValidation)
    }

    private var validationMessage: String? {
        guard showsValidation else { return nil }
        if case .failure(let message) = StudyIDCheck.validateNewStudyID(studyID) { return message }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Study code")
                        .font(.sectionTitle)
                        .foregroundStyle(Theme.Colors.ink)
                    TextField("For example S-014", text: $studyID)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .fieldStyle()
                        .accessibilityLabel("Study code")
                    Text("Use the code the study gave this patient. Letters, digits and dashes, up to 16 characters. Never a name, date of birth or record number.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(studyID.count) of \(StudySession.maxStudyIDLength)")
                        .font(.support)
                        .foregroundStyle(Theme.Colors.graduation)
                    if let message = storageMessage ?? validationMessage {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                            Image(systemName: "exclamationmark.triangle")
                                .accessibilityHidden(true)
                            Text(message)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.body)
                        .foregroundStyle(Theme.Colors.caution)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, Theme.Spacing.margin)
                .padding(.vertical, Theme.Spacing.l)
            }
            .background(Theme.Colors.tray)
            .navigationTitle("New study session")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: studyID) { storageMessage = nil }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.s) {
                    Button("Create session and continue") { create() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Cancel") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, Theme.Spacing.margin)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.Colors.tray)
            }
        }
    }

    private func create() {
        switch StudyIDCheck.validateNewStudyID(studyID) {
        case .success(let id):
            do {
                let created = try stores.study.create(studyID: id)
                onCreated(created)
                dismiss()
            } catch {
                storageMessage = "Could not create the session: \(error.localizedDescription)"
            }
        case .failure:
            showsValidation = true
        }
    }
}
