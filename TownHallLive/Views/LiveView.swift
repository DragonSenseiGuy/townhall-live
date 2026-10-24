import SwiftUI

struct LiveView: View {
    let store: DataStore
    var session: DemoSessionController
    var votes: MockVoteController

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if !session.steps.isEmpty { DemoSessionCard(session: session, store: store) }
                agendaSection
                if let focus = session.currentArticleID.flatMap({ store.article(id: $0) }) ?? liveArticles.first {
                    MockVoteCard(article: focus, votes: votes)
                }
                recentSessionsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle("TownHall Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Theme.navy)
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

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LiveBadge()
                Spacer()
                if let meeting = liveMeeting {
                    Text(meeting.date)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Text(liveMeeting?.title ?? "No meeting scheduled")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.navy)
            if let url = liveMeeting?.streamURL, let link = URL(string: url) {
                Link(destination: link) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle")
                        Text("Watch on Town TV")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.navy)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Agenda")
            VStack(spacing: 8) {
                ForEach(liveArticles) { article in
                    agendaRow(article)
                }
                if liveArticles.isEmpty {
                    Text("Agenda appears here. Replace the seed data with the town's real warrant.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func agendaRow(_ article: WarrantArticle) -> some View {
        let isCurrent = session.currentArticleID == article.id
        return NavigationLink(value: article.id) {
            HStack(spacing: 12) {
                Text("\(article.number)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? Theme.gold : Theme.inkSecondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(article.title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(Theme.navy)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        CategoryChip(text: article.category)
                        if let outcome = article.officialOutcome {
                            OutcomeChip(result: outcome.result)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.divider)
                    .opacity(0.9)
            }
            .padding(12)
            .background(
                isCurrent ? Theme.goldSoft.opacity(0.55) : Theme.parchmentCard,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isCurrent ? Theme.gold.opacity(0.6) : Theme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Recent sessions")
            ForEach(store.meetings.filter { $0.status != "live" }) { meeting in
                NavigationLink(value: meeting.id) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting.title)
                                .font(.subheadline)
                                .foregroundStyle(Theme.navy)
                                .multilineTextAlignment(.leading)
                            Text(meeting.date)
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary.opacity(0.6))
                    }
                    .padding(12)
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
