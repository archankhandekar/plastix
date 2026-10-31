import SwiftUI
import SymmetryModels

/// Screen 1: every session as a card, each with its study code and the one thing to do
/// next. The whole card opens the session; a long press offers Delete.
struct SessionListView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @Binding var path: NavigationPath

    @State private var showingNewSession = false
    @State private var pendingDelete: StudySession?
    /// Set by the New session sheet; pushed once the sheet has fully dismissed.
    @State private var pendingPush: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if store.sessions.isEmpty {
                    emptyState
                }
                ForEach(store.sessions) { session in
                    sessionCard(session)
                }
                settingsRow
                ResearchNoticeBanner()
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Colors.paper)
        .navigationTitle("Sessions")
        .navigationDestination(for: UUID.self) { id in SessionView(sessionID: id) }
        .safeAreaInset(edge: .bottom) {
            Button("New session") { showingNewSession = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(Theme.Spacing.m)
                .background(.bar)
        }
        .sheet(isPresented: $showingNewSession, onDismiss: {
            if let id = pendingPush {
                pendingPush = nil
                path.append(id)
            }
        }) {
            NewSessionSheet(onCreated: { created in pendingPush = created.id })
        }
        .confirmationDialog("Delete this session and all of its images?",
                            isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                if let s = pendingDelete { store.delete(s) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .alert("Storage problem", isPresented: .init(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
    }

    // MARK: - Cards

    private var emptyState: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text("No sessions yet")
                .font(.stepTitle)
                .foregroundStyle(Theme.Colors.ink)
            Text("A session is one patient, identified only by a study code. It holds every set of photos you take for that patient.")
                .font(.body)
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Create the first session") { showingNewSession = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func sessionCard(_ session: StudySession) -> some View {
        let progress = SessionProgress(session: session,
                                       settings: settings.reportSettings,
                                       hasCompared: ComparedFlag.isSet(sessionID: session.id))
        return NavigationLink(value: session.id) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(session.studyID)
                        .font(.stepTitle)
                        .foregroundStyle(Theme.Colors.ink)
                    Text("Started \(session.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.slate)
                    Text(progress.summaryLine)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.slate)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
            .cardStyle()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) { pendingDelete = session }
        }
        .accessibilityElement(children: .combine)
    }

    private var settingsRow: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Settings")
                        .font(.stepTitle)
                        .foregroundStyle(Theme.Colors.ink)
                    Text("You do not need to change anything here to use the app.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.slate)
            }
            .tapTarget()
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

/// Screen 2: one field for the study code, with the rule beneath it and a live counter.
/// On success the caller receives the new session and the sheet dismisses itself.
struct NewSessionSheet: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    let onCreated: (StudySession) -> Void

    @State private var studyID = ""
    @State private var message: String?

    init(onCreated: @escaping (StudySession) -> Void) {
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Study code")
                        .font(.stepTitle)
                        .foregroundStyle(Theme.Colors.ink)
                    TextField("For example S-014", text: $studyID)
                        .font(.body)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .fieldStyle()
                    Text("Use the code the study gave this patient. Letters, digits and dashes, up to 16 characters. Never a name, date of birth or record number.")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(studyID.count) of \(StudySession.maxStudyIDLength)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.slate)
                    if let message {
                        GuidanceCard(kind: .caution, body: message)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Colors.paper)
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.s) {
                    Button("Create session and continue") { create() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Cancel") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(Theme.Spacing.m)
                .background(.bar)
            }
        }
    }

    private func create() {
        switch StudySession.validateStudyID(studyID) {
        case .success(let id):
            do {
                let created = try store.create(studyID: id)
                onCreated(created)
                dismiss()
            } catch {
                message = "Could not create the session: \(error.localizedDescription)"
            }
        case .failure(let error):
            message = error.message
        }
    }
}
