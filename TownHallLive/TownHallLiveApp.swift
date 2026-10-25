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
    @State private var store = DataStore()
    @State private var session = DemoSessionController()
    @State private var votes = MockVoteController()
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
            ArticleDetailView(store: store, articleID: id)
        } else if store.history(id: id) != nil {
            HistoryDetailView(store: store, voteID: id)
        } else {
            MeetingDetailView(store: store, meetingID: id)
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $livePath) {
                LiveView(store: store, session: session, votes: votes)
                    .navigationDestination(for: String.self, destination: destination)
                    .navigationDestination(for: DevRoute.self) { route in
                        SettingsView()
                    }
            }
            .tabItem { Label("Live", systemImage: "dot.radiowaves.right") }
            .tag(0)

            NavigationStack(path: $warrantsPath) {
                WarrantsView(store: store)
                    .navigationDestination(for: String.self, destination: destination)
                    .navigationDestination(for: DevRoute.self) { route in
                        SettingsView()
                    }
            }
            .tabItem { Label("Warrants", systemImage: "doc.text") }
            .tag(1)

            NavigationStack(path: $historyPath) {
                HistoryView(store: store)
                    .navigationDestination(for: String.self, destination: destination)
                    .navigationDestination(for: DevRoute.self) { route in
                        SettingsView()
                    }
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(2)
        }
        .tint(Theme.ink)
        .preferredColorScheme(.light)
        .task {
            store.load()
            session.configure(with: store.data?.demoSession ?? [])
            applyDevOpen()
        }
    }

    private func applyDevOpen() {
        guard let open = UserDefaults.standard.string(forKey: "thl.open") else { return }
        switch open {
        case "settings": livePath.append(DevRoute.settings)
        default:
            if store.article(id: open) != nil { warrantsPath.append(open) }
            else if store.history(id: open) != nil { historyPath.append(open) }
        }
        UserDefaults.standard.removeObject(forKey: "thl.open")
    }
}

// Non-string dev route.
enum DevRoute: Hashable { case settings }
