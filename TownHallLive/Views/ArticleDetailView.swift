import SwiftUI

// The full library: every Town Meeting's warrant articles, grouped by meeting.
struct WarrantsView: View {
    let store: DataStore

    var body: some View {
        VerticalPage {
            VStack(alignment: .leading, spacing: 24) {
                LiveStatusLine(store: store)
                ForEach(store.townMeetings) { meeting in
                    meetingSection(meeting)
                }
                if store.articles.isEmpty {
                    Text(L("Warrant articles appear here once the town publishes a warrant."))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .refreshable { await store.refresh() }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(L("Warrants"))
        .toolbarBackground(Theme.canvas, for: .navigationBar)
    }

    @ViewBuilder
    private func meetingSection(_ meeting: Meeting) -> some View {
        let articles = store.articles(in: meeting.id)
        if !articles.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meetingNameText(meeting.title))
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.ink)
                    Text(dateLineText(meeting.date))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(articles) { article in
                    NavigationLink(value: article.id) {
                        ArticleRow(article: article, isCurrent: false)
                    }
                    .pressable()
                }
            }
        }
    }
}

// One article: a single plain-English explanation, the official text right
// under it, then money, the official outcome beside the reader's own stance,
// and links back into history.
struct ArticleDetailView: View {
    let store: DataStore
    let articleID: String
    var stances: StanceStore

    @State private var aiError: String?
    private var settings: AppSettings { .shared }

    private var article: WarrantArticle? { store.article(id: articleID) }

    var body: some View {
        VerticalPage {
            if let article {
                content(article)
            } else {
                Text(L("Article not found."))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(Theme.pagePadding)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(article.map { L("Article %@", String($0.number)) } ?? L("Article"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        // No plain-English version yet: write one when an AI key is set.
        .task(id: articleID) {
            guard let article, !article.isTranslated, settings.hasAPIKey else { return }
            aiError = await store.generatePlainEnglish(for: article)
        }
        // Interface in another language: translate the explanation into it.
        .task(id: translationTaskID) {
            // The booklet excerpt is replaced by an AI version first; translate that.
            guard let article, settings.language != .english, settings.hasAPIKey,
                  article.isTranslated else { return }
            await store.translateContent(article.plainEnglish, language: settings.language)
        }
    }

    private var translationTaskID: String {
        "\(articleID)|\(settings.language.rawValue)|\(article.map { TextHash.of($0.plainEnglish.summary) } ?? "")"
    }

    @ViewBuilder
    private func content(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            heroCard(article)
            plainEnglishCard(article)
            officialTextCard(article)

            if let impact = article.financialImpact {
                financialCard(impact)
            }

            outcomeCard(article)

            if !article.relatedHistoricalVoteIDs.isEmpty {
                historyCard(article)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 4)
        .padding(.bottom, 40)
    }

    private func heroCard(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                NumberTile(number: article.number, highlighted: true)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Warrant article"))
                        .font(.caption2.weight(.semibold))
                        .tracking(0.7)
                        .foregroundStyle(Theme.accent)
                    Text(meetingDate)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Text(LT(article.title))
                .font(Theme.titleFont)
                .foregroundStyle(Theme.ink)
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
        article.flatMap { store.meeting(id: $0.meetingID)?.date }.map(dateLineText) ?? ""
    }

    // MARK: Plain English (one section)

    private func plainEnglishCard(_ article: WarrantArticle) -> some View {
        let generating = store.isGenerating(article)
        let language = settings.language
        let translated = store.localizedPlain(article.plainEnglish, language: language)
        // Not translated yet: the app's own fallback sentences still come from the catalog.
        let plain = translated ?? PlainEnglish(
            summary: article.plainEnglish.summary,
            keyTakeaways: article.plainEnglish.keyTakeaways.map(LT),
            votingYesMeans: LT(article.plainEnglish.votingYesMeans),
            votingNoMeans: LT(article.plainEnglish.votingNoMeans)
        )
        let translating = store.isTranslatingContent(article.plainEnglish, language: language)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(text: L("In plain English"))
                Spacer(minLength: 8)
                if settings.hasAPIKey, !generating {
                    Button {
                        Task { aiError = await store.generatePlainEnglish(for: article) }
                    } label: {
                        Label(L("Regenerate with AI"), systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if generating {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accent)
                    Text(L("Writing a plain-English version…"))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            } else if !article.isTranslated {
                note(settings.hasAPIKey
                     ? L("This is the warrant booklet's own summary.")
                     : L("This is the warrant booklet's own summary. Add an AI key in Settings for a plain-English version."))
            }
            if let aiError, !generating {
                Text(L("Couldn't write a plain-English version right now.") + " " + aiError)
                    .font(.caption)
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if language != .english, translated == nil {
                if translating {
                    note(L("Translating…"))
                } else if !settings.hasAPIKey {
                    note(L("Shown in English. Add an AI key in Settings to translate explanations."))
                }
            }

            Text(plain.summary)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(plain.keyTakeaways.enumerated()), id: \.offset) { _, takeaway in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 8)
                        Text(takeaway)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider().overlay(Theme.divider)

            VStack(alignment: .leading, spacing: 10) {
                meaningRow(symbol: "checkmark", label: L("Vote yes"), color: Theme.green, text: plain.votingYesMeans)
                meaningRow(symbol: "xmark", label: L("Vote no"), color: Theme.red, text: plain.votingNoMeans)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func meaningRow(symbol: String, label: String, color: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                Text(label)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Official text

    private func officialTextCard(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Official text"))
            if settings.language != .english {
                officialRecordNote
            }
            Text(article.originalText)
                .font(.footnote.leading(.loose))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let source = article.sourceURL, let link = URL(string: source) {
                Link(L("Open the warrant document"), destination: link)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func financialCard(_ impact: FinancialImpact) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "banknote.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: L("Financial impact"))
                Text(impact.amount)
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(LT(impact.explanation))
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

    // MARK: Outcome + your stance

    private func outcomeCard(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(text: L("Official outcome"))
                if let outcome = article.officialOutcome {
                    HStack(spacing: 8) {
                        OutcomeChip(result: outcome.result)
                        if let tally = outcome.tally {
                            Text(tallyText(tally))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(LT(outcome.sourceNote))
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("Not voted yet. The result appears here once the town publishes it."))
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().overlay(Theme.divider)

            StanceView(articleID: article.id, stances: stances)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func historyCard(_ article: WarrantArticle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: L("Synced with history"))
            ForEach(article.relatedHistoricalVoteIDs, id: \.self) { id in
                if let vote = store.history(id: id) {
                    NavigationLink(value: vote.id) {
                        HStack(alignment: .top, spacing: 10) {
                            Text(verbatim: "\(vote.year)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .bold()
                                .foregroundStyle(Theme.accent)
                            Text(LT(vote.title))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            OutcomeChip(result: vote.outcome)
                        }
                        .padding(10)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .pressable()
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// "Where do you stand?" — the reader's own Yay / Nay / Abstain, saved on this
// device only and shown beside the real outcome. No community numbers.
struct StanceView: View {
    let articleID: String
    var stances: StanceStore

    private var stance: VoteChoice? { stances.stance(for: articleID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: L("Where do you stand?"))
            HStack(spacing: 8) {
                ForEach(VoteChoice.allCases) { choice in
                    button(choice)
                }
            }
            Text(stance == nil
                 ? L("Saved only on this phone. Official votes happen in person at Town Meeting.")
                 : L("Your stance: %@ · saved only on this phone.", label(stance!)))
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: stance)
        .sensoryFeedback(.selection, trigger: stance)
    }

    private func label(_ choice: VoteChoice) -> String { L(choice.rawValue) }

    private func button(_ choice: VoteChoice) -> some View {
        let selected = stance == choice
        let color: Color = choice == .yay ? Theme.green : (choice == .nay ? Theme.red : Theme.inkSecondary)
        return Button {
            stances.toggle(choice, for: articleID)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: choice == .yay ? "checkmark" : (choice == .nay ? "xmark" : "minus"))
                    .font(.footnote.weight(.bold))
                Text(label(choice))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? .white : color)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(selected ? color : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .pressable()
    }
}
