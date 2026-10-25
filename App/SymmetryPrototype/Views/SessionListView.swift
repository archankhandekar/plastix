import SwiftUI
import SymmetryModels

struct SessionListView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var showingNewSession = false
    @State private var pendingDelete: StudySession?

    var body: some View {
        List {
            if store.sessions.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("No sessions yet").font(.headline)
                    Text("Start one with a non-identifying study ID to begin capturing.")
                        .foregroundStyle(Theme.Colors.slate)
                }
                .padding(.vertical, Theme.Spacing.m)
            }
            ForEach(store.sessions) { session in
                NavigationLink(value: session.id) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(session.studyID).font(.headline)
                        Text("\(session.captureSets.count) capture set\(session.captureSets.count == 1 ? "" : "s"), started \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.slate)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .swipeActions {
                    Button(role: .destructive) { pendingDelete = session } label: { Label("Delete", systemImage: "trash") }
                }
            }
            Section { ResearchNoticeBanner() }
        }
        .navigationTitle("Sessions")
        .navigationDestination(for: UUID.self) { id in SessionView(sessionID: id) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewSession = true } label: { Label("New session", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingNewSession) { NewSessionSheet() }
        .confirmationDialog("Delete this session and all of its images?", isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
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
}

struct NewSessionSheet: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var studyID = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Study ID").font(.headline)
                TextField("For example S-014", text: $studyID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .fieldStyle()
                Text("Use the study's own code. Do not enter names, dates of birth or record numbers.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.slate)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(Theme.Colors.unreliable)
                }
                Spacer()
                Button("Create session") { create() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(Theme.Spacing.l)
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func create() {
        switch StudySession.validateStudyID(studyID) {
        case .success(let id):
            do { try store.create(studyID: id); dismiss() } catch { message = "Could not create the session: \(error.localizedDescription)" }
        case .failure(let error):
            message = error.message
        }
    }
}
