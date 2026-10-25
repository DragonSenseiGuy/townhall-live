import SwiftUI

struct LiveView: View {
    let store: DataStore
    var session: DemoSessionController
    var votes: MockVoteController
    // Dev/test only: bumps after a hook-cast vote to trigger the auto-scroll.
    @State private var voteScrollPrompt = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    hero

                    if !session.steps.isEmpty { DemoSessionCard(session: session, store: store) }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(text: "Agenda")
                        VStack(spacing: 0) {
                            ForEach(liveArticles) { article in
                                NavigationLink(value: article.id) {
                                    ArticleRow(article: article, isCurrent: session.currentArticleID == article.id)
                                        .padding(.horizontal, Theme.cardPadding)
                                }
                                .pressable()
                                if article.id != liveArticles.last?.id {
                                    Rectangle()
                                        .fill(Theme.divider)
                                        .frame(height: 1)
                                        .padding(.leading, Theme.cardPadding + ArticleRow.gutter + 12)
                                }
                            }
                        }
                        if liveArticles.isEmpty {
                            Text("The agenda appears here once a meeting goes live.")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }

                    if let focus = session.currentArticleID.flatMap({ store.article(id: $0) }) ?? liveArticles.first {
                        MockVoteCard(article: focus, votes: votes)
                            .id("thl-vote-card")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(text: "Recent sessions")
                        VStack(spacing: 0) {
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
                                    .padding(.horizontal, Theme.cardPadding)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .pressable()
                                if meeting.id != store.meetings.filter({ $0.status != "live" }).last?.id {
                                    Rectangle()
                                        .fill(Theme.divider)
                                        .frame(height: 1)
                                        .padding(.leading, Theme.cardPadding)
                                }
                            }
                        }
                        .card()
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
            .onChange(of: voteScrollPrompt) { _, _ in
                // Dev/test hook: simctl can't scroll — bring the vote card
                // (and its clerk's-record stamp) into the screenshot frame.
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo("thl-vote-card", anchor: .top)
                }
            }
            // Dev/test hook: cast a mock vote without tap automation.
            .onAppear {
                if UserDefaults.standard.bool(forKey: "thl.castVote"), let article = store.article(id: "a4") {
                    votes.cast(.yay, for: article.id)
                    withAnimation(.easeOut(duration: 0.35)) { voteScrollPrompt += 1 }
                    UserDefaults.standard.removeObject(forKey: "thl.castVote")
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
    }

    private var liveMeeting: Meeting? {
        store.meetings.first { $0.status == "live" } ?? store.meetings.first
    }

    private var liveArticles: [WarrantArticle] {
        guard let meeting = liveMeeting else { return [] }
        return store.articles.filter { $0.meetingID == meeting.id }.sorted { $0.number < $1.number }
    }

    // Uber-style hero: uncarded, heavy type, two pill CTAs, and the session
    // record — real, sourced facts of the actual meeting set in the
    // monospaced "record" register. No template would print these lines.
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
                    .pressable()
                }
            }

            if liveMeeting?.moderator != nil || liveMeeting?.sessionNote != nil {
                VStack(alignment: .leading, spacing: 5) {
                    Rectangle().fill(Theme.divider).frame(height: 1)
                    if let moderator = liveMeeting?.moderator {
                        recordLine(key: "MODERATOR", value: moderator)
                    }
                    if let note = liveMeeting?.sessionNote {
                        recordLine(key: "SESSION", value: note)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func recordLine(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(Theme.recordFont)
                .foregroundStyle(Theme.inkSecondary.opacity(0.75))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(Theme.recordFont)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
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
