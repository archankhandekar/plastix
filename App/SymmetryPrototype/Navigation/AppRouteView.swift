import SwiftUI

/// Maps every `AppRoute` to its screen. This is the only place that names the screen types;
/// screens navigate by appending routes to `AppNavigator.path`.
///
/// Every session route applies `.sessionScope(ref.kind)`, which picks the study or the
/// practice `SessionStore` and sets `\.sessionKind`. It reads `SessionStores` from the
/// environment, so the root must inject `SessionStores` above the NavigationStack.
struct AppRouteView: View {
    let route: AppRoute

    init(route: AppRoute) {
        self.route = route
    }

    var body: some View {
        switch route {
        case .session(let ref):
            SessionView(sessionID: ref.id)
                .sessionScope(ref.kind)
        case .symmetry(let ref, let setID, let tab, let focus, let mode):
            SymmetryResultView(sessionID: ref.id, setID: setID, tab: tab, focus: focus, obliqueMode: mode)
                .sessionScope(ref.kind)
        case .acrossStages(let ref):
            AcrossStagesView(sessionID: ref.id)
                .sessionScope(ref.kind)
        case .compare(let ref, let earlierID, let laterID):
            ComparisonView(sessionID: ref.id, earlierID: earlierID, laterID: laterID)
                .sessionScope(ref.kind)
        case .markPoints(let ref, let setID, let captureID, let showTruth):
            LandmarkEditorView(sessionID: ref.id, setID: setID, captureID: captureID, showTruth: showTruth)
                .sessionScope(ref.kind)
        case .review(let ref, let setID):
            ReviewView(sessionID: ref.id, setID: setID)
                .sessionScope(ref.kind)
        case .export(let ref):
            ExportView(sessionID: ref.id)
                .sessionScope(ref.kind)
        case .settings:
            SettingsView()
                .sessionScope(.study)
        case .explainer:
            MetricExplainerSheet()
        }
    }
}
