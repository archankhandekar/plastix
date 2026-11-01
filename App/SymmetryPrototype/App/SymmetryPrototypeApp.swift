import SwiftUI

@main
struct SymmetryPrototypeApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var navigator: AppNavigator
    @StateObject private var stores: SessionStores
    #if DEBUG
    /// Set only when the DEBUG route harness was launched with -UIRoute.
    private let harness: RouteHarness.Launch?
    #endif

    init() {
        #if DEBUG
        if let route = LaunchRoute.current {
            let launch = RouteHarness.makeEnvironment(route)
            harness = launch
            _settings = StateObject(wrappedValue: launch.settings)
            _navigator = StateObject(wrappedValue: launch.navigator)
            _stores = StateObject(wrappedValue: launch.stores)
            return
        }
        harness = nil
        #endif
        _settings = StateObject(wrappedValue: AppSettings())
        _navigator = StateObject(wrappedValue: AppNavigator())
        _stores = StateObject(wrappedValue: SessionStores(study: SessionStore(), practice: PracticeStore()))
    }

    var body: some Scene {
        WindowGroup {
            root
                // sessionScope reads SessionStores, so SessionStores is injected above it.
                .sessionScope(.study)
                .environmentObject(stores)
                .environmentObject(navigator)
                .environmentObject(settings)
                .tint(Theme.Colors.drape)
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if let harness {
            RootView().routeHarness(harness)
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}

/// The app's one NavigationStack, driven by `AppNavigator.path`, with the research notice
/// shown once over it.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var navigator: AppNavigator
    @EnvironmentObject private var stores: SessionStores
    /// Passed into the notice cover, which does not inherit an overridden text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack(path: $navigator.path) {
            SessionListView()
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteView(route: route)
                }
        }
        .fullScreenCover(isPresented: .init(get: { !settings.researchNoticeAccepted }, set: { _ in })) {
            ResearchNoticeView()
                .environmentObject(settings)
                .environmentObject(navigator)
                .environmentObject(stores)
                .dynamicTypeSize(dynamicTypeSize)
        }
    }
}
