import Foundation

// Single source of truth for the UI. Loads instantly from the last live
// snapshot (Caches) merged over the bundled JSON, then refreshes from the
// town's website in the background. Network or parse failures never clear
// what's on screen — they're logged and the previous data stays.
@Observable
final class DataStore {
    private(set) var data: TownData?
    /// When live data last arrived from the town's sources (nil = bundled only).
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var isLiveConfigured = false

    // History archive (past results abstracts), loaded lazily.
    private(set) var scrapedHistory: [HistoricalVote] = []
    private(set) var isLoadingHistory = false
    /// Archive documents still to read in the current pass (for the progress line).
    private(set) var historyPending = 0
    private(set) var historyConfigured = false

    // AI content translations into the interface language: "lang|hash" → text.
    private(set) var contentTranslations: [String: PlainEnglish] = [:]
    private(set) var translatingKeys: Set<String> = []
    /// Articles whose plain-English version is being generated right now.
    private(set) var generating: Set<String> = []

    @ObservationIgnored private var bundled: TownData?
    @ObservationIgnored private var snapshot: LiveSnapshot?
    @ObservationIgnored private var translations: [String: PlainEnglish] = [:]
    @ObservationIgnored private var sources = TownSources.current()
    @ObservationIgnored private var isTranslating = false
    @ObservationIgnored private var historyCache: HistoryCacheFile?

    var articles: [WarrantArticle] { data?.articles ?? [] }
    var meetings: [Meeting] { data?.meetings ?? [] }
    var curatedHistory: [HistoricalVote] { data?.historicalVotes ?? [] }
    var historicalVotes: [HistoricalVote] { HistoryMapper.merge(curated: curatedHistory, scraped: scrapedHistory) }

    func article(id: String) -> WarrantArticle? { articles.first { $0.id == id } }
    func history(id: String) -> HistoricalVote? {
        curatedHistory.first { $0.id == id } ?? scrapedHistory.first { $0.id == id }
    }
    func meeting(id: String) -> Meeting? { meetings.first { $0.id == id } }
    func articles(in meetingID: String) -> [WarrantArticle] {
        articles.filter { $0.meetingID == meetingID }.sorted { $0.number < $1.number }
    }

    /// Town Meetings (not calendar items or recordings), newest first.
    var townMeetings: [Meeting] { meetings.filter(\.isTownMeeting) }

    /// Upcoming sessions from the town calendar, plus a Town Meeting whose
    /// warrant date is still ahead.
    var upcomingMeetings: [Meeting] {
        let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        var out = meetings.filter { $0.kind == "calendar" }
        if let next = townMeetings.first(where: { ($0.parsedDate ?? .distantPast) >= today }),
           !out.contains(where: { $0.parsedDate == next.parsedDate }) {
            out.insert(next, at: 0)
        }
        return out.sorted { ($0.parsedDate ?? .distantFuture) < ($1.parsedDate ?? .distantFuture) }
    }

    /// The most recent Town Meeting that has already happened.
    var lastTownMeeting: Meeting? {
        let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        return townMeetings.first { ($0.parsedDate ?? .distantPast) < today }
    }

    var recordings: [Meeting] { meetings.filter { $0.kind == "recording" } }

    func load() {
        guard data == nil else { return }
        if let url = Bundle.main.url(forResource: "townhall_data", withExtension: "json"),
           let raw = try? Data(contentsOf: url) {
            do {
                bundled = try JSONDecoder().decode(TownData.self, from: raw)
            } catch {
                LiveLog.log("bundled data unreadable: \(error.localizedDescription)")
            }
        }
        sources = TownSources.current()
        isLiveConfigured = sources.isConfigured
        historyConfigured = sources.resultsArchiveURL != nil
        translations = LiveCache.load([String: PlainEnglish].self, from: LiveCache.translationsFile) ?? [:]
        contentTranslations = LiveCache.load([String: PlainEnglish].self, from: LiveCache.contentTranslationsFile) ?? [:]
        if sources.isConfigured,
           let cached = LiveCache.load(LiveSnapshot.self, from: LiveCache.snapshotFile),
           cached.sourceKey == sources.cacheKey {
            snapshot = cached
            lastUpdated = cached.fetchedAt
        }
        if let cached = LiveCache.load(HistoryCacheFile.self, from: LiveCache.historyFile),
           cached.sourceKey == sources.historyKey {
            historyCache = cached
            publishHistory()
        }
        rebuild()
    }

    /// Pulls fresh data from the configured town sources. Safe to call often.
    func refresh() async {
        guard !isRefreshing else { return }
        let latest = TownSources.current() // picks up Settings changes
        if latest != sources {
            sources = latest
            if snapshot?.sourceKey != latest.cacheKey {
                snapshot = nil
                lastUpdated = nil
            }
            if historyCache?.sourceKey != latest.historyKey {
                historyCache = nil
                scrapedHistory = []
            }
            historyConfigured = latest.resultsArchiveURL != nil
            rebuild()
        }
        isLiveConfigured = sources.isConfigured
        guard sources.isConfigured else { return }

        isRefreshing = true
        let fresh = await TownScraper(sources: sources).refresh(previous: snapshot)
        isRefreshing = false

        if fresh.sourceKey == sources.cacheKey, !fresh.isEmpty, fresh.fetchedAt != nil {
            snapshot = fresh
            lastUpdated = fresh.fetchedAt
            LiveCache.save(fresh, to: LiveCache.snapshotFile)
            rebuild()
        } else {
            LiveLog.log("refresh produced no live data; keeping what's on screen")
        }
        await translatePending()
    }

    /// Refresh when the last live data is older than `maxAge`.
    func refreshIfStale(maxAge: TimeInterval = 30 * 60) async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge { return }
        await refresh()
    }

    /// Stores an AI plain-English version keyed by the article text, so it
    /// survives relaunches and refreshes.
    func cacheTranslation(_ plain: PlainEnglish, for article: WarrantArticle) {
        translations[TextHash.of(article.originalText)] = plain
        LiveCache.save(translations, to: LiveCache.translationsFile)
        rebuild()
    }

    // MARK: - Plain English (generation + interface-language translation)

    func isGenerating(_ article: WarrantArticle) -> Bool { generating.contains(article.id) }

    /// Generates (or regenerates) the plain-English version through AIService.
    /// Returns an error message on failure.
    @discardableResult
    func generatePlainEnglish(for article: WarrantArticle) async -> String? {
        guard AppSettings.shared.hasAPIKey, !generating.contains(article.id) else { return nil }
        generating.insert(article.id)
        defer { generating.remove(article.id) }
        do {
            let plain = try await AIService().translate(article: article)
            cacheTranslation(plain, for: article)
            return nil
        } catch {
            LiveLog.log("AI plain English failed for article \(article.number): \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    private func contentKey(_ plain: PlainEnglish, _ language: AppLanguage) -> String {
        let text = ([plain.summary] + plain.keyTakeaways + [plain.votingYesMeans, plain.votingNoMeans]).joined(separator: "\n")
        return "\(language.rawValue)|\(TextHash.of(text))"
    }

    /// The plain-English text in the interface language, when an AI
    /// translation into it is cached. English needs none.
    func localizedPlain(_ plain: PlainEnglish, language: AppLanguage) -> PlainEnglish? {
        guard language != .english else { return plain }
        return contentTranslations[contentKey(plain, language)]
    }

    func isTranslatingContent(_ plain: PlainEnglish, language: AppLanguage) -> Bool {
        translatingKeys.contains(contentKey(plain, language))
    }

    /// Translates the plain-English text into the interface language (AI key
    /// required), caching per language + text hash.
    func translateContent(_ plain: PlainEnglish, language: AppLanguage) async {
        guard language != .english, AppSettings.shared.hasAPIKey else { return }
        let key = contentKey(plain, language)
        guard contentTranslations[key] == nil, !translatingKeys.contains(key) else { return }
        translatingKeys.insert(key)
        defer { translatingKeys.remove(key) }
        do {
            let translated = try await AIService().translate(plain: plain, into: language)
            contentTranslations[key] = translated
            LiveCache.save(contentTranslations, to: LiveCache.contentTranslationsFile)
        } catch {
            LiveLog.log("AI translation into \(language.englishName) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - History archive

    /// Reads the town's results archive in the background: re-lists at most
    /// daily, then parses each not-yet-cached abstract, newest first,
    /// publishing as it goes. Unreadable PDFs are skipped (retried weekly).
    func loadHistory(force: Bool = false) async {
        guard !isLoadingHistory else { return }
        let current = TownSources.current()
        if current != sources { sources = current }
        historyConfigured = sources.resultsArchiveURL != nil
        guard historyConfigured else { return }
        isLoadingHistory = true
        defer {
            isLoadingHistory = false
            historyPending = 0
        }

        var cache = historyCache?.sourceKey == sources.historyKey ? historyCache! : HistoryCacheFile(sourceKey: sources.historyKey)
        let scraper = HistoryScraper(sources: sources)
        let listingAge = cache.listedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if force || listingAge > 24 * 3600 || cache.results.isEmpty {
            if let listing = await scraper.listing(), !listing.results.isEmpty {
                cache.results = listing.results
                if !listing.warrants.isEmpty { cache.warrants = listing.warrants }
                cache.listedAt = Date()
            }
        }

        let week: TimeInterval = 7 * 24 * 3600
        let todo = cache.results.filter { entry in
            guard let doc = cache.documents[entry.id] else { return true }
            return doc.unreadable && Date().timeIntervalSince(doc.fetchedAt) > week
        }
        historyPending = todo.count
        historyCache = cache
        publishHistory()

        var failures = 0
        for entry in todo {
            if let doc = await scraper.document(for: entry, warrants: cache.warrants) {
                cache.documents[entry.id] = doc
                historyCache = cache
                LiveCache.save(cache, to: LiveCache.historyFile)
                publishHistory()
                failures = 0
            } else {
                failures += 1
                if failures >= 3 { break } // offline — try again next time
            }
            historyPending = max(0, historyPending - 1)
        }
        historyCache = cache
        LiveCache.save(cache, to: LiveCache.historyFile)
    }

    var historyYears: [Int] {
        Array(Set(historicalVotes.map(\.year))).sorted(by: >)
    }

    private func publishHistory() {
        guard let cache = historyCache else { scrapedHistory = []; return }
        let order = Dictionary(cache.results.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        scrapedHistory = cache.documents.values
            .filter { !$0.unreadable }
            .sorted { (order[$0.entry.id] ?? .max) < (order[$1.entry.id] ?? .max) }
            .flatMap(HistoryMapper.votes(from:))
    }

    // MARK: - Private

    private func rebuild() {
        let base = bundled ?? TownData(
            town: TownInfo(name: "Town", state: "Massachusetts"),
            meetings: [], articles: [], historicalVotes: []
        )
        data = LiveMerger.merge(
            bundled: base,
            snapshot: sources.isConfigured ? snapshot : nil,
            translations: translations,
            townName: sources.townName,
            state: sources.state
        )
    }

    /// With an AI key set, writes plain-English versions for scraped articles
    /// that only have a warrant excerpt. One at a time; stops after repeated failures.
    private func translatePending() async {
        guard !isTranslating, AppSettings.shared.hasAPIKey else { return }
        isTranslating = true
        defer { isTranslating = false }
        var failures = 0
        let pending = articles.filter { !$0.isTranslated }
        for article in pending.prefix(60) {
            if await generatePlainEnglish(for: article) == nil {
                failures = 0
            } else {
                failures += 1
                if failures >= 3 { break }
            }
        }
    }
}
