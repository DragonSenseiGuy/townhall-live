import SwiftUI

struct LiveView: View {
    let store: DataStore
    var session: DemoSessionController
    var votes: MockVoteController

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
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
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(text: "Recent sessions")
                    ForEach(store.meetings.filter { $0.status != "live" }) { meeting in
                        NavigationLink(value: meeting.id) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meeting.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.navy)
                                        .multilineTextAlignment(.leading)
                                    Text(meeting.date)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.divider)
                            }
                            .padding(14)
                            .card()
                        }
                        .pressable()
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle("TownHall Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.parchment, for: .navigationBar)
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
        VStack(spacing: 12) {
            TownCrest()
            VStack(spacing: 5) {
                Text("TOWN · MASSACHUSETTS")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.gold)
                Text(liveMeeting?.title ?? "No meeting scheduled")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.navy)
                    .multilineTextAlignment(.center)
                Text(liveMeeting?.date ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                LiveBadge()
                Spacer(minLength: 0)
                if let url = liveMeeting?.streamURL, let link = URL(string: url) {
                    Link(destination: link) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.rectangle")
                            Text("Watch on Town TV")
                                .font(.footnote.weight(.medium))
                        }
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.cardPadding)
        .card()
    }
}

// Drawn crest: double gold ring, drawn town-hall facade with star finial.
// Pure shapes — nothing depends on symbol availability.
struct TownCrest: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.goldBright, lineWidth: 2)
            Circle()
                .strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1)
                .padding(3)
            VStack(spacing: 7) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.goldBright)
                CrestFacade()
            }
        }
        .frame(width: 56, height: 56)
        .background(Theme.parchmentCard, in: Circle())
        .accessibilityHidden(true)
    }
}

private struct CrestFacade: View {
    var body: some View {
        VStack(spacing: 2) {
            CrestPediment()
                .fill(Theme.navy)
                .frame(width: 30, height: 9)
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    VStack(spacing: 2) {
                        Circle()
                            .fill(index % 2 == 0 ? Theme.goldBright : Theme.navy)
                            .frame(width: 3, height: 3)
                        Rectangle()
                            .fill(Theme.navy)
                            .frame(width: 4, height: 11)
                    }
                }
            }
            Rectangle()
                .fill(Theme.goldBright)
                .frame(width: 32, height: 3)
        }
    }
}

nonisolated struct CrestPediment: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
