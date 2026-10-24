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
        TabView {
            NavigationStack {
                LiveView(store: store, session: session, votes: votes)
                    .navigationDestination(for: String.self, destination: destination)
            }
            .tabItem { Label("Live", systemImage: "dot.radiowaves.right") }

            NavigationStack {
                WarrantsView(store: store)
                    .navigationDestination(for: String.self, destination: destination)
            }
            .tabItem { Label("Warrants", systemImage: "doc.text") }

            NavigationStack {
                HistoryView(store: store)
                    .navigationDestination(for: String.self, destination: destination)
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .tint(Theme.navy)
        .environment(\.colorScheme, .light)
        .task {
            store.load()
            session.configure(with: store.data?.demoSession ?? [])
        }
    }
}
