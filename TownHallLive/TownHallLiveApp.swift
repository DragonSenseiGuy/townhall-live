import SwiftUI

@main
struct TownHallLiveApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = DataStore()
    @State private var stances = StanceStore()
    private var settings: AppSettings { .shared }
    // Dev hook: `simctl launch <udid> <bundle> -thl.startTab 1` opens a specific
    // tab for CLI screenshots/videos.
    @State private var tab: Int
    // Dev hooks for CLI tests (no tap automation): -thl.open settings|<id>
    // pushes a route after load; navigation paths stay empty in normal use.
    @State private var livePath = NavigationPath()
    @State private var warrantsPath = NavigationPath()
    @State private var historyPath = NavigationPath()

    init() {
        _tab = State(initialValue: UserDefaults.standard.integer(forKey: "thl.startTab"))
    }

    /// Article ids, historical-vote ids, and meeting ids share the String
    /// navigation namespace; resolve by precedence.
    @ViewBuilder
    private func destination(for id: String) -> some View {
        if store.article(id: id) != nil {
            ArticleDetailView(store: store, articleID: id, stances: stances)
        } else if store.history(id: id) != nil {
            HistoryDetailView(store: store, voteID: id)
        } else {
            MeetingDetailView(store: store, meetingID: id)
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $livePath) {
                LiveView(store: store, openWarrants: { tab = 1 })
                    .navigationDestination(for: String.self, destination: destination)
                    .navigationDestination(for: DevRoute.self) { route in
                        SettingsView()
                    }
            }
            .tabItem { Label(L("Live"), systemImage: "dot.radiowaves.right") }
            .tag(0)

            NavigationStack(path: $warrantsPath) {
                WarrantsView(store: store)
                    .navigationDestination(for: String.self, destination: destination)
                    .navigationDestination(for: DevRoute.self) { route in
                        SettingsView()
                    }
            }
            .tabItem { Label(L("Warrants"), systemImage: "doc.text") }
            .tag(1)

            NavigationStack(path: $historyPath) {
                HistoryView(store: store)
                    .navigationDestination(for: String.self, destination: destination)
                    .navigationDestination(for: DevRoute.self) { route in
                        SettingsView()
                    }
            }
            .tabItem { Label(L("History"), systemImage: "clock.arrow.circlepath") }
            .tag(2)
        }
        .tint(Theme.ink)
        .preferredColorScheme(.light)
        // The language chosen in Settings drives the whole interface: strings
        // (via L()), system formatting, and right-to-left layout for Arabic.
        .environment(\.locale, settings.language.locale)
        .environment(\.layoutDirection, settings.language.layoutDirection)
        .task {
            store.load()
            applyDevOpen()
            // Cached/bundled data is already on screen; now fetch live.
            await store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, store.data != nil else { return }
            Task { await store.refreshIfStale() }
        }
    }

    private func applyDevOpen() {
        // Consume the key first: if the process dies before the defaults
        // deletion flushes, a stale hook would keep re-pushing the route.
        let open = UserDefaults.standard.string(forKey: "thl.open")
        UserDefaults.standard.removeObject(forKey: "thl.open")
        guard let open else { return }
        switch open {
        case "settings":
            tab = 0
            livePath.append(DevRoute.settings)
        default:
            // The pushed route lives on one stack, so select the tab that
            // shows it — otherwise the destination opens invisibly.
            if store.article(id: open) != nil {
                tab = 1
                warrantsPath.append(open)
            } else if store.history(id: open) != nil {
                tab = 2
                historyPath.append(open)
            }
        }
    }
}

// Non-string dev route.
enum DevRoute: Hashable { case settings }
