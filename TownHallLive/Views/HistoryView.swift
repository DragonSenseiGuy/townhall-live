import SwiftUI

struct HistoryView: View {
    let store: DataStore
    @State private var searchText = ""

    private var grouped: [(year: Int, votes: [HistoricalVote])] {
        let filtered = searchText.isEmpty
            ? store.historicalVotes
            : store.historicalVotes.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.summary.localizedCaseInsensitiveContains(searchText)
                    || $0.category.localizedCaseInsensitiveContains(searchText)
            }
        let sorted = filtered.sorted { $0.year > $1.year }
        var out: [(Int, [HistoricalVote])] = []
        var currentYear = -1
        for vote in sorted {
            if vote.year != currentYear {
                out.append((vote.year, [vote]))
                currentYear = vote.year
            } else {
                out[out.count - 1].1.append(vote)
            }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(grouped, id: \.year) { group in
                    yearBanner(group.year)
                    ForEach(group.votes) { vote in
                        NavigationLink(value: vote.id) {
                            HistoryRow(vote: vote)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle("History")
        .toolbarBackground(Theme.parchment, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search past town decisions")
    }

    private func yearBanner(_ year: Int) -> some View {
        HStack(spacing: 10) {
            Text(String(year))
                .font(.system(.title2, design: .serif, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.navy)
            Rectangle()
                .fill(Theme.gold.opacity(0.6))
                .frame(height: 1)
            Spacer(minLength: 8)
        }
        .padding(.top, 20)
    }
}

struct HistoryRow: View {
    let vote: HistoricalVote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .strokeBorder(vote.outcome == "passed" ? Theme.green : Theme.burgundy, lineWidth: 2)
                .frame(width: 10, height: 10)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(vote.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.navy)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    CategoryChip(text: vote.category)
                    Text(vote.tally)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.divider)
        }
        .padding(.vertical, 8)
    }
}

struct HistoryDetailView: View {
    let store: DataStore
    let voteID: String

    private var vote: HistoricalVote? { store.history(id: voteID) }

    private var relatedArticles: [WarrantArticle] {
        store.articles.filter { $0.relatedHistoricalVoteIDs.contains(voteID) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let vote {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            CategoryChip(text: vote.category)
                            OutcomeChip(result: vote.outcome)
                        }
                        Text(vote.title)
                            .font(Theme.titleFont)
                            .foregroundStyle(Theme.navy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(vote.meetingName) · \(vote.year)")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.gold)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel(text: "Why it matters today")
                            Text(vote.relevanceNote)
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "The vote")
                        Text(vote.summary)
                            .font(.body)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Result: \(vote.outcome) · \(vote.tally)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.navy)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    if !relatedArticles.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: "On the warrant now")
                            ForEach(relatedArticles) { article in
                                NavigationLink(value: article.id) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(article.displayNumber)
                                                .font(.caption2.weight(.bold))
                                                .tracking(0.5)
                                                .foregroundStyle(Theme.gold)
                                            Text(article.title)
                                                .font(.footnote.weight(.medium))
                                                .foregroundStyle(Theme.navy)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Theme.divider)
                                    }
                                    .padding(10)
                                    .background(Theme.parchment, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle("Decision")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.parchment, for: .navigationBar)
    }
}
