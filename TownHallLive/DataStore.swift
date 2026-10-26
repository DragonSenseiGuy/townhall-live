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

    @ObservationIgnored private var bundled: TownData?
    @ObservationIgnored private var snapshot: LiveSnapshot?
    @ObservationIgnored private var translations: [String: PlainEnglish] = [:]
    @ObservationIgnored private var sources = TownSources.current()
    @ObservationIgnored private var isTranslating = false

    var articles: [WarrantArticle] { data?.articles ?? [] }
    var meetings: [Meeting] { data?.meetings ?? [] }
    var historicalVotes: [HistoricalVote] { data?.historicalVotes ?? [] }

    func article(id: String) -> WarrantArticle? { articles.first { $0.id == id } }
    func history(id: String) -> HistoricalVote? { historicalVotes.first { $0.id == id } }
    func meeting(id: String) -> Meeting? { meetings.first { $0.id == id } }

    /// The meeting the Live tab leads with.
    var heroMeeting: Meeting? { meetings.first { $0.status == "live" } ?? meetings.first }

    /// The simulated replay only runs over articles of the meeting on screen.
    var demoSteps: [DemoStep] {
        guard let hero = heroMeeting else { return [] }
        return (data?.demoSession ?? []).filter { article(id: $0.articleID)?.meetingID == hero.id }
    }

    func load() {
        guard data == nil else { return }
        if let url = Bundle.main.url(forResource: "townhall_data", withExtension: "json"),
           let raw = try? Data(contentsOf: url) {
            bundled = try? JSONDecoder().decode(TownData.self, from: raw)
        }
        sources = TownSources.current()
        isLiveConfigured = sources.isConfigured
        translations = LiveCache.load([String: PlainEnglish].self, from: LiveCache.translationsFile) ?? [:]
        if sources.isConfigured,
           let cached = LiveCache.load(LiveSnapshot.self, from: LiveCache.snapshotFile),
           cached.sourceKey == sources.cacheKey {
            snapshot = cached
            lastUpdated = cached.fetchedAt
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

    /// Stores an AI translation (from the background pass or the article screen)
    /// keyed by the article text, so it survives relaunches and refreshes.
    func cacheTranslation(_ plain: PlainEnglish, for article: WarrantArticle) {
        translations[TextHash.of(article.originalText)] = plain
        LiveCache.save(translations, to: LiveCache.translationsFile)
        rebuild()
    }

    // MARK: - Private

    private func rebuild() {
        let base = bundled ?? TownData(
            town: TownInfo(name: "Town", state: "Massachusetts"),
            meetings: [], articles: [], historicalVotes: [], demoSession: []
        )
        data = LiveMerger.merge(
            bundled: base,
            snapshot: sources.isConfigured ? snapshot : nil,
            translations: translations,
            townName: sources.townName,
            state: sources.state
        )
    }

    /// With an AI key set, translates scraped articles that only have a
    /// warrant excerpt. One at a time; stops after repeated failures.
    private func translatePending() async {
        guard !isTranslating, AppSettings.shared.hasAPIKey else { return }
        isTranslating = true
        defer { isTranslating = false }
        var failures = 0
        let pending = articles.filter { !$0.isTranslated }
        for article in pending.prefix(60) {
            do {
                let plain = try await AIService().translate(article: article)
                cacheTranslation(plain, for: article)
                failures = 0
            } catch {
                failures += 1
                LiveLog.log("AI translation failed for article \(article.number): \(error.localizedDescription)")
                if failures >= 3 { break }
            }
        }
    }
}
