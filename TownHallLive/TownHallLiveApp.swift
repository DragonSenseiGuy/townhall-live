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
            NavigationStack {
                LiveView(store: store, session: session, votes: votes)
                    .navigationDestination(for: String.self, destination: destination)
            }
            .tabItem { Label("Live", systemImage: "dot.radiowaves.right") }
            .tag(0)

            NavigationStack {
                WarrantsView(store: store)
                    .navigationDestination(for: String.self, destination: destination)
            }
            .tabItem { Label("Warrants", systemImage: "doc.text") }
            .tag(1)

            NavigationStack {
                HistoryView(store: store)
                    .navigationDestination(for: String.self, destination: destination)
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(2)
        }
        .tint(Theme.navy)
        .preferredColorScheme(.light)
        .task {
            store.load()
            session.configure(with: store.data?.demoSession ?? [])
        }
    }
}
