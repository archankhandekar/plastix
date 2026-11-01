import Foundation
import SwiftUI
import SymmetryModels

/// Whether a session is real study data or the virtual patient. Every screen reads it from
/// the environment; `sessionScope(_:)` sets it together with the matching `SessionStore`.
enum SessionKind: String, Hashable {
    case study, practice
}

private struct SessionKindKey: EnvironmentKey {
    static let defaultValue: SessionKind = .study
}

extension EnvironmentValues {
    var sessionKind: SessionKind {
        get { self[SessionKindKey.self] }
        set { self[SessionKindKey.self] = newValue }
    }
}

/// A session plus the store it lives in.
struct SessionRef: Hashable {
    let id: UUID
    let kind: SessionKind
}

/// The two tabs of the symmetry result.
enum SymmetryTab: String, Hashable, CaseIterable {
    case frontal, obliques
}

/// How the two oblique photos are shown next to each other.
enum ObliqueMode: String, Hashable, CaseIterable {
    case sideBySide = "pair", wipe, switchSide = "switch"
}

/// Every pushable destination of the one NavigationStack. Screens navigate by appending
/// these values to `AppNavigator.path`, never by naming each other's view types.
enum AppRoute: Hashable {
    case session(SessionRef)
    case symmetry(SessionRef, setID: UUID, tab: SymmetryTab = .frontal, focus: PlateLayer = .all, obliqueMode: ObliqueMode = .sideBySide)
    case acrossStages(SessionRef)
    case compare(SessionRef, earlierID: UUID?, laterID: UUID?)
    case markPoints(SessionRef, setID: UUID, captureID: UUID, showTruth: Bool = false)
    case review(SessionRef, setID: UUID)
    case export(SessionRef)
    case settings
    case explainer
}

/// Owns the navigation path of the app's single NavigationStack.
@MainActor
final class AppNavigator: ObservableObject {
    @Published var path: [AppRoute] = []
    /// Set by `popToSession(_:performNext:)` so session home performs its next action
    /// (for example opening the camera) once it is back on screen. Home clears it.
    @Published var performNextOnHome = false

    func push(_ r: AppRoute) {
        path.append(r)
    }

    /// Truncates the path to just after the last `.session(ref)` entry. When the session is
    /// not on the path, the path becomes that session home alone.
    func popToSession(_ ref: SessionRef, performNext: Bool = false) {
        if let i = path.lastIndex(of: .session(ref)) {
            path = Array(path[...i])
        } else {
            path = [.session(ref)]
        }
        performNextOnHome = performNext
    }

    func popToRoot() {
        path = []
    }
}

/// The two separate session stores: real study data and the virtual patient.
@MainActor
final class SessionStores: ObservableObject {
    let study: SessionStore
    let practice: PracticeStore

    init(study: SessionStore, practice: PracticeStore) {
        self.study = study
        self.practice = practice
    }

    func store(for kind: SessionKind) -> SessionStore {
        switch kind {
        case .study: return study
        case .practice: return practice.store
        }
    }

    /// Deletes every study session and the virtual patient, with their UI flags.
    func deleteAllData() {
        for session in study.sessions { UIFlags.clear(session: session) }
        study.deleteAll()
        practice.deleteAll()
    }
}

/// Injects the `SessionStore` for one kind and the matching `\.sessionKind`.
struct SessionScopeModifier: ViewModifier {
    @EnvironmentObject var stores: SessionStores
    let kind: SessionKind

    func body(content: Content) -> some View {
        content
            .environmentObject(stores.store(for: kind))
            .environment(\.sessionKind, kind)
    }
}

extension View {
    /// Every screen keeps using `@EnvironmentObject SessionStore`; this decides which store that is.
    func sessionScope(_ kind: SessionKind) -> some View {
        modifier(SessionScopeModifier(kind: kind))
    }
}
