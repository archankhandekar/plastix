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
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            SessionListView()
        }
        .fullScreenCover(isPresented: .init(get: { !settings.researchNoticeAccepted }, set: { _ in })) {
            ResearchNoticeView()
        }
    }
}
