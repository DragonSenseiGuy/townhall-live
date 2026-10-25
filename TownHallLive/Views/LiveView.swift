import SwiftUI

struct LiveView: View {
    let store: DataStore
    var session: DemoSessionController
    var votes: MockVoteController

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                if !session.steps.isEmpty { DemoSessionCard(session: session, store: store) }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(text: "Agenda")
                    ForEach(liveArticles) { article in
                        NavigationLink(value: article.id) {
                            ArticleRow(article: article, isCurrent: session.currentArticleID == article.id)
                        }
                        .pressable()
                    }
                    if liveArticles.isEmpty {
                        Text("Agenda appears here. Replace the seed data with the town's real warrant.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                if let focus = session.currentArticleID.flatMap({ store.article(id: $0) }) ?? liveArticles.first {
                    MockVoteCard(article: focus, votes: votes)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(text: "Recent sessions")
                    ForEach(store.meetings.filter { $0.status != "live" }) { meeting in
                        NavigationLink(value: meeting.id) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meeting.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading)
                                    Text(meeting.date)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.inkSecondary.opacity(0.5))
                            }
                            .padding(13)
                            .card()
                        }
                        .pressable()
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("TownHall Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        // Dev/test hook: cast a mock vote without tap automation.
        .onAppear {
            if UserDefaults.standard.bool(forKey: "thl.castVote"), let article = store.article(id: "a4") {
                votes.cast(.yay, for: article.id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private var liveMeeting: Meeting? {
        store.meetings.first { $0.status == "live" } ?? store.meetings.first
    }

    private var liveArticles: [WarrantArticle] {
        guard let meeting = liveMeeting else { return [] }
        return store.articles.filter { $0.meetingID == meeting.id }.sorted { $0.number < $1.number }
    }

    // Uber-style hero: uncarded, heavy type, two pill CTAs.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                SectionLabel(text: "Town · Massachusetts")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(liveMeeting?.title ?? "No meeting scheduled")
                    .font(Theme.displayFont)
                    .foregroundStyle(Theme.ink)
                Text(liveMeeting?.date ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
            HStack(spacing: 10) {
                LiveBadge()
                Spacer(minLength: 0)
                if let url = liveMeeting?.streamURL, let link = URL(string: url) {
                    Link(destination: link) {
                        pillLabel("Watch on Town TV", systemImage: "play.rectangle", filled: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func pillLabel(_ text: String, systemImage: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(filled ? .white : Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(filled ? Theme.ink : Theme.tile, in: Capsule())
    }
}
