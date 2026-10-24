import SwiftUI

struct WarrantsView: View {
    let store: DataStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(store.meetings) { meeting in
                    meetingSection(meeting)
                }
                if store.articles.isEmpty {
                    Text("Warrants appear here. Bundle your town's warrant data to fill this tab.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle("Warrants")
        .toolbarBackground(Theme.parchment, for: .navigationBar)
    }

    @ViewBuilder
    private func meetingSection(_ meeting: Meeting) -> some View {
        let articles = store.articles.filter { $0.meetingID == meeting.id }.sorted { $0.number < $1.number }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title)
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.navy)
                    Text(meeting.date)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                if meeting.status == "live" { LiveBadge() }
            }
            .padding(.bottom, 2)
            ForEach(articles) { article in
                NavigationLink(value: article.id) {
                    ArticleRow(article: article, isCurrent: false)
                }
                .pressable()
            }
        }
    }
}

// One article: original legal text beside its plain-English translation,
// financial impact, official outcome, and links back into history.
struct ArticleDetailView: View {
    let store: DataStore
    let articleID: String

    @State private var aiState: AIState = .idle

    enum AIState {
        case idle
        case loading
        case done(PlainEnglish)
        case failed(String)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    private var article: WarrantArticle? { store.article(id: articleID) }

    var body: some View {
        ScrollView {
            if let article {
                content(article)
            } else {
                Text("Article not found.")
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.parchment.ignoresSafeArea())
        .navigationTitle(article?.displayNumber ?? "Article")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.parchment, for: .navigationBar)
        .onDisappear { if aiState.isLoading { aiState = .idle } }
    }

    @ViewBuilder
    private func content(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            heroCard(article)

            plainEnglishCard(article.plainEnglish)

            if let impact = article.financialImpact {
                financialCard(impact)
            }

            aiCard(article)

            if let outcome = article.officialOutcome {
                outcomeCard(outcome)
            }

            if !article.relatedHistoricalVoteIDs.isEmpty {
                historyCard(article)
            }

            originalTextCard(article)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 40)
    }

    private func heroCard(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                NumberSeal(number: article.number, highlighted: true)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("WARRANT ARTICLE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.gold)
                    Text(meetingDate)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
            }
            Text(article.title)
                .font(Theme.titleFont)
                .foregroundStyle(Theme.navy)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                CategoryChip(text: article.category)
                if let outcome = article.officialOutcome {
                    OutcomeChip(result: outcome.result)
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var meetingDate: String {
        article.flatMap { store.meeting(id: $0.meetingID)?.date } ?? ""
    }

    private func plainEnglishCard(_ plain: PlainEnglish) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "In plain English")
            Text(aiState.isLoading ? "Translating with AI…" : plain.summary)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(plain.keyTakeaways.enumerated()), id: \.offset) { _, takeaway in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Theme.gold).frame(width: 5, height: 5).padding(.top, 8)
                        Text(takeaway)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider().overlay(Theme.divider)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VOTE YES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.green)
                    Text(plain.votingYesMeans)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(Theme.divider).frame(width: 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("VOTE NO")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.burgundy)
                    Text(plain.votingNoMeans)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.cardPadding)
        .card()
    }

    private func financialCard(_ impact: FinancialImpact) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "banknote.fill")
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Financial impact")
                Text(impact.amount)
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(Theme.navy)
                Text(impact.explanation)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func aiCard(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Live AI translation")
                Spacer()
                if !AppSettings.shared.hasAPIKey {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Text("Add a free key")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
            switch aiState {
            case .idle:
                Text("Re-translate this article live through the configured endpoint (Hack Club AI by default).")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                Button {
                    regenerate(article)
                } label: {
                    Label("Translate with AI", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.navy, in: Capsule())
                }
                .pressable()
                .disabled(!AppSettings.shared.hasAPIKey)
                .opacity(AppSettings.shared.hasAPIKey ? 1 : 0.5)
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.gold)
                    Text("Asking the model for a plain-English rewrite…")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            case .done(let plain):
                VStack(alignment: .leading, spacing: 8) {
                    Text(plain.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plain.keyTakeaways.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.burgundy)
            }
        }
        .padding(Theme.cardPadding)
        .card()
    }

    private func regenerate(_ article: WarrantArticle) {
        aiState = .loading
        Task {
            do {
                let plain = try await AIService().translate(article: article)
                withAnimation(.easeOut(duration: 0.25)) { aiState = .done(plain) }
            } catch {
                withAnimation(.easeOut(duration: 0.25)) { aiState = .failed(error.localizedDescription) }
            }
        }
    }

    private func outcomeCard(_ outcome: OfficialOutcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(text: "Official outcome")
            HStack(spacing: 8) {
                OutcomeChip(result: outcome.result)
                if let tally = outcome.tally {
                    Text(tally)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(outcome.sourceNote)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func historyCard(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "Synced with history")
            ForEach(article.relatedHistoricalVoteIDs, id: \.self) { id in
                if let vote = store.history(id: id) {
                    NavigationLink(value: vote.id) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(vote.year)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .bold()
                                .foregroundStyle(Theme.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vote.title)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Theme.navy)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Town meeting voted to \(vote.outcome)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            OutcomeChip(result: vote.outcome)
                        }
                        .padding(10)
                        .background(Theme.parchment, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .pressable()
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func originalTextCard(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(text: "Original warrant text")
            Text(article.originalText)
                .font(.caption.leading(.loose))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
