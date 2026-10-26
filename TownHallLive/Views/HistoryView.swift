import SwiftUI

// Every past Town Meeting decision the town's archive has in readable form,
// plus the curated entries that explain why a decision still matters.
struct HistoryView: View {
    let store: DataStore
    @State private var searchText = ""
    @State private var year: Int? = nil

    private var grouped: [(year: Int, votes: [HistoricalVote])] {
        var filtered = store.historicalVotes
        if let year { filtered = filtered.filter { $0.year == year } }
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.summary.localizedCaseInsensitiveContains(searchText)
                    || $0.category.localizedCaseInsensitiveContains(searchText)
                    || L($0.category).localizedCaseInsensitiveContains(searchText)
                    || $0.meetingName.localizedCaseInsensitiveContains(searchText)
                    || LT($0.title).localizedCaseInsensitiveContains(searchText)
                    || meetingNameText($0.meetingName).localizedCaseInsensitiveContains(searchText)
            }
        }
        // Stable: newest year first, curated notes first within a year, then article order.
        let sorted = filtered.enumerated().sorted { a, b in
            if a.element.year != b.element.year { return a.element.year > b.element.year }
            return a.offset < b.offset
        }.map(\.element)
        var out: [(Int, [HistoricalVote])] = []
        for vote in sorted {
            if let last = out.last, last.0 == vote.year {
                out[out.count - 1].1.append(vote)
            } else {
                out.append((vote.year, [vote]))
            }
        }
        return out
    }

    var body: some View {
        VerticalPage {
            LazyVStack(alignment: .leading, spacing: 0) {
                statusLine
                ForEach(grouped, id: \.year) { group in
                    yearBanner(group.year, count: group.votes.count)
                    ForEach(group.votes) { vote in
                        NavigationLink(value: vote.id) {
                            HistoryRow(vote: vote)
                        }
                        .pressable()
                    }
                }
                if grouped.isEmpty, !store.isLoadingHistory {
                    Text(L("No decisions match."))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .refreshable { await store.loadHistory(force: true) }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(L("History"))
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .searchable(text: $searchText, prompt: L("Search past town decisions"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(L("Year"), selection: $year) {
                        Text(L("All years")).tag(Int?.none)
                        ForEach(store.historyYears, id: \.self) { y in
                            Text(verbatim: String(y)).tag(Int?.some(y))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(year.map { String($0) } ?? L("All years"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
        }
        // Unstructured so switching tabs doesn't cancel a half-read archive.
        .onAppear { Task { await store.loadHistory() } }
    }

    @ViewBuilder
    private var statusLine: some View {
        if store.isLoadingHistory {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.accent)
                Text(store.historyPending > 0
                     ? L("Reading past results from the town archive… %@ left", String(store.historyPending))
                     : L("Checking the town archive…"))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        } else if store.historyConfigured {
            Text(L("Decisions: %@ · from the town's results archive", String(store.historicalVotes.count)))
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.top, 4)
        }
    }

    private func yearBanner(_ year: Int, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: String(year))
                .font(.system(.title2, design: .default, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(verbatim: String(count))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.top, 20)
    }
}

func outcomeSymbol(_ result: String) -> (name: String, color: Color) {
    switch result {
    case "passed": ("checkmark.circle.fill", Theme.green)
    case "failed": ("xmark.circle.fill", Theme.red)
    default: ("minus.circle.fill", Theme.inkSecondary)
    }
}

struct HistoryRow: View {
    let vote: HistoricalVote

    var body: some View {
        let symbol = outcomeSymbol(vote.outcome)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol.name)
                .font(.subheadline)
                .foregroundStyle(symbol.color)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(LT(vote.title))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(meetingLine)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    CategoryChip(text: vote.category)
                    if !vote.tally.isEmpty {
                        Text(tallyText(vote.tally))
                            .font(.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary.opacity(0.5))
        }
        .padding(.vertical, 10)
    }

    private var meetingLine: String {
        var line = meetingNameText(vote.meetingName)
        if let n = vote.articleNumber { line += " · " + L("Article %@", String(n)) }
        return line
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
        VerticalPage {
            VStack(alignment: .leading, spacing: 16) {
                if let vote {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            CategoryChip(text: vote.category)
                            OutcomeChip(result: vote.outcome)
                        }
                        Text(LT(vote.title))
                            .font(Theme.titleFont)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        // verbatim: Int interpolation localizes to "2,022"
                        Text(verbatim: "\(meetingNameText(vote.meetingName.components(separatedBy: " · ").first ?? vote.meetingName)) · \(vote.year)")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    if !vote.relevanceNote.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Theme.accent)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                SectionLabel(text: L("Why it matters today"))
                                Text(LT(vote.relevanceNote))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(Theme.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: L("The vote"))
                        if !vote.summary.isEmpty {
                            // Curated entries carry a plain-language explanation; scraped
                            // ones quote the warrant, which stays in the original English.
                            let isOfficialWording = vote.relevanceNote.isEmpty
                            if isOfficialWording, AppSettings.shared.language != .english {
                                officialRecordNote
                            }
                            Text(isOfficialWording ? vote.summary : LT(vote.summary))
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            OutcomeChip(result: vote.outcome)
                            if !vote.tally.isEmpty {
                                Text(tallyText(vote.tally))
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let source = vote.sourceURL, let link = URL(string: source) {
                            Link(L("Open the official results"), destination: link)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.top, 4)
                        }
                    }
                    .padding(Theme.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    if !relatedArticles.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: L("On the warrant now"))
                            ForEach(relatedArticles) { article in
                                NavigationLink(value: article.id) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(L("Article %@", String(article.number)))
                                                .font(.caption2.weight(.bold))
                                                .tracking(0.5)
                                                .foregroundStyle(Theme.accent)
                                            Text(LT(article.title))
                                                .font(.footnote.weight(.medium))
                                                .foregroundStyle(Theme.ink)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 0)
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
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(L("Decision"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
    }
}
