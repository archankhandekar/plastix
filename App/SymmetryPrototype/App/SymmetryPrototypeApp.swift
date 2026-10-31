import SwiftUI

@main
struct SymmetryPrototypeApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .tint(Theme.Colors.accent)
        }
    }
}

/// Shows the research-use notice once, then the session list.
///
/// The navigation path lives here so the session list can push a freshly created
/// session after its sheet has dismissed.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            SessionListView(path: $path)
        }
        .fullScreenCover(isPresented: .init(get: { !settings.researchNoticeAccepted }, set: { _ in })) {
            ResearchNoticeView()
        }
    }
}
