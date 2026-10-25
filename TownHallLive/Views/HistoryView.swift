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
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("History")
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search past town decisions")
    }

    private func yearBanner(_ year: Int) -> some View {
        Text(String(year))
            .font(.system(.title2, design: .default, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .padding(.top, 20)
    }
}

struct HistoryRow: View {
    let vote: HistoricalVote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: vote.outcome == "passed" ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(vote.outcome == "passed" ? Theme.green : Theme.red)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(vote.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary.opacity(0.5))
        }
        .padding(.vertical, 10)
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
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        // verbatim: Int interpolation localizes to "2,022"
                        Text(verbatim: "\(vote.meetingName) · \(vote.year)")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel(text: "Why it matters today")
                            Text(vote.relevanceNote)
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Theme.cardPadding)
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
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(Theme.cardPadding)
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
                                                .foregroundStyle(Theme.accent)
                                            Text(article.title)
                                                .font(.footnote.weight(.medium))
                                                .foregroundStyle(Theme.ink)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(Theme.inkSecondary.opacity(0.5))
                                    }
                                    .padding(10)
                                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .pressable()
                            }
                        }
                        .padding(Theme.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Decision")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
    }
}
