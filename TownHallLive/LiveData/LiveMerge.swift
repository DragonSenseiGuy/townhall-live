import Foundation

// What one live refresh produced, cached on disk as JSON. The app always
// renders `LiveMerger.merge(bundled:snapshot:…)`, so a partial or stale
// snapshot only ever adds to the bundled data — it can't blank the UI.

nonisolated struct LiveWarrant: Codable, Sendable {
    let meetingID: String
    let sourceURL: String
    let meetingDate: String?
    let articles: [ParsedArticle]
}

nonisolated struct LiveResults: Codable, Sendable {
    let meetingID: String
    let sourceURL: String
    let meetingDates: String?
    let outcomes: [ParsedOutcome]
}

nonisolated struct LiveSnapshot: Codable, Sendable {
    /// Identifies the configured sources; a snapshot from other sources is ignored.
    var sourceKey: String
    /// Last time at least one source answered.
    var fetchedAt: Date?
    var townMeetings: [TownMeetingLinks] = []
    var warrant: LiveWarrant?
    var results: LiveResults?
    var upcoming: [CalendarEvent] = []
    var recordings: [Recording] = []

    var isEmpty: Bool {
        townMeetings.isEmpty && warrant == nil && results == nil && upcoming.isEmpty && recordings.isEmpty
    }
}

nonisolated enum TextHash {
    /// Stable FNV-1a 64-bit hash, hex — the cache key for AI translations.
    static func of(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

nonisolated enum LiveMerger {
    static func merge(
        bundled: TownData,
        snapshot: LiveSnapshot?,
        translations: [String: PlainEnglish],
        townName: String? = nil,
        state: String? = nil
    ) -> TownData {
        let town = TownInfo(name: townName ?? bundled.town.name, state: state ?? bundled.town.state)
        guard let snapshot, !snapshot.isEmpty else {
            return TownData(town: town, meetings: bundled.meetings, articles: bundled.articles,
                            historicalVotes: bundled.historicalVotes, demoSession: bundled.demoSession)
        }
        let checked = snapshot.fetchedAt.map(shortDate) ?? "recently"

        // Meetings ------------------------------------------------------------
        var meetings: [Meeting] = []
        var usedVideoIDs = Set<String>()

        for event in snapshot.upcoming.prefix(3) {
            meetings.append(Meeting(id: event.id, title: event.title, date: event.dateText, status: "upcoming",
                                    streamURL: nil, kind: "calendar"))
        }

        let townMeetings = snapshot.townMeetings.sorted { $0.year > $1.year }
        for (index, links) in townMeetings.enumerated() {
            let old = bundled.meetings.first { $0.id == links.id }
            var date = old?.date ?? String(links.year)
            if let w = snapshot.warrant, w.meetingID == links.id, let d = w.meetingDate {
                date = d
            } else if old == nil, let r = snapshot.results, r.meetingID == links.id, let d = r.meetingDates {
                date = d
            }
            let stream = links.videoURLs.first ?? old?.streamURL
            links.videoURLs.compactMap(FeedMapper.youTubeID).forEach { usedVideoIDs.insert($0) }
            meetings.append(Meeting(
                id: links.id,
                title: links.title,
                date: date,
                status: index == 0 ? "live" : (index == 1 ? "recent" : "past"),
                streamURL: stream
            ))
        }
        let liveIDs = Set(meetings.map(\.id))
        let hasLiveHero = meetings.contains { $0.status == "live" }
        for old in bundled.meetings where !liveIDs.contains(old.id) {
            // Only one hero meeting: demote bundled "live" when the site gave us one.
            let status = hasLiveHero && old.status == "live" ? "recent" : old.status
            meetings.append(Meeting(id: old.id, title: old.title, date: old.date, status: status,
                                    streamURL: old.streamURL, kind: old.kind))
            if let url = old.streamURL, let id = FeedMapper.youTubeID(url) { usedVideoIDs.insert(id) }
        }

        for rec in snapshot.recordings where !usedVideoIDs.contains(rec.videoID) {
            meetings.append(Meeting(
                id: "yt-\(rec.videoID)",
                title: rec.title,
                date: rec.published.map(longDate) ?? "Recording",
                status: "past",
                streamURL: rec.url,
                kind: "recording"
            ))
        }

        // Articles ------------------------------------------------------------
        var articles: [WarrantArticle] = []
        var covered = Set<String>() // "\(meetingID)#\(number)"
        let results = snapshot.results
        func outcome(meetingID: String, number: Int, bundledOutcome: OfficialOutcome?) -> OfficialOutcome? {
            guard let results, results.meetingID == meetingID,
                  let o = results.outcomes.first(where: { $0.number == number }) else { return bundledOutcome }
            // The town's summary sheet usually prints no counts; keep a curated
            // count only when it agrees with the live result.
            let tally = o.tally.map { "\(o.label) \($0)" }
                ?? (bundledOutcome?.result == o.result ? bundledOutcome?.tally : nil)
            return OfficialOutcome(result: o.result, tally: tally,
                                   sourceNote: "Town Meeting results summary, town website (checked \(checked)).")
        }

        if let warrant = snapshot.warrant {
            for parsed in warrant.articles {
                let old = bundled.articles.first { $0.meetingID == warrant.meetingID && $0.number == parsed.number }
                covered.insert("\(warrant.meetingID)#\(parsed.number)")
                let hash = TextHash.of(parsed.legalText)
                let plain: PlainEnglish
                let source: String?
                if let curated = old?.plainEnglish {
                    plain = curated
                    source = old?.plainEnglishSource
                } else if let ai = translations[hash] {
                    plain = ai
                    source = "ai"
                } else {
                    plain = fallbackPlainEnglish(parsed)
                    source = "excerpt"
                }
                articles.append(WarrantArticle(
                    id: old?.id ?? "\(warrant.meetingID)-a\(parsed.number)",
                    meetingID: warrant.meetingID,
                    number: parsed.number,
                    title: parsed.title,
                    category: old?.category ?? category(for: parsed.title),
                    originalText: parsed.legalText,
                    plainEnglish: plain,
                    financialImpact: old?.financialImpact ?? financialImpact(parsed),
                    officialOutcome: outcome(meetingID: warrant.meetingID, number: parsed.number, bundledOutcome: old?.officialOutcome),
                    simulatedTally: old?.simulatedTally ?? simulatedTally(parsed.number),
                    relatedHistoricalVoteIDs: old?.relatedHistoricalVoteIDs ?? [],
                    plainEnglishSource: source,
                    sourceURL: warrant.sourceURL
                ))
            }
        }
        for old in bundled.articles where !covered.contains("\(old.meetingID)#\(old.number)") {
            articles.append(WarrantArticle(
                id: old.id, meetingID: old.meetingID, number: old.number, title: old.title,
                category: old.category, originalText: old.originalText, plainEnglish: old.plainEnglish,
                financialImpact: old.financialImpact,
                officialOutcome: outcome(meetingID: old.meetingID, number: old.number, bundledOutcome: old.officialOutcome),
                simulatedTally: old.simulatedTally, relatedHistoricalVoteIDs: old.relatedHistoricalVoteIDs,
                plainEnglishSource: old.plainEnglishSource, sourceURL: old.sourceURL
            ))
        }

        return TownData(town: town, meetings: meetings, articles: articles,
                        historicalVotes: bundled.historicalVotes, demoSession: bundled.demoSession)
    }

    // MARK: Fallbacks (no AI)

    static func fallbackPlainEnglish(_ a: ParsedArticle) -> PlainEnglish {
        let summary = a.bookletSummary.map { TextClean.sentences($0, count: 2) }
            ?? TextClean.sentences(a.legalText, count: 1)
        var takeaways: [String] = []
        if let impact = financialImpact(a) { takeaways.append("Dollar amount in the article: \(impact.amount)") }
        if let vote = a.voteRequirement {
            takeaways.append(RX.contains("two.?thirds|2/3", in: vote) ? "Needs a two-thirds majority to pass" : "Needs a simple majority to pass")
        }
        if let recs = a.recommendations { takeaways.append("Recommendations: \(recs)") }
        if takeaways.isEmpty { takeaways.append("See the original warrant text below for the full details") }
        return PlainEnglish(
            summary: summary,
            keyTakeaways: takeaways,
            votingYesMeans: "A yes vote approves the article as written in the warrant.",
            votingNoMeans: "A no vote rejects the article as written."
        )
    }

    static func financialImpact(_ a: ParsedArticle) -> FinancialImpact? {
        guard let largest = a.amounts.max(by: { TextClean.dollarValue($0) < TextClean.dollarValue($1) }) else { return nil }
        let distinct = Set(a.amounts).count
        let explanation = distinct > 1
            ? "Largest of \(distinct) dollar figures in the warrant text — see the original text for each line item."
            : "Dollar figure stated in the warrant text."
        return FinancialImpact(amount: largest, explanation: explanation)
    }

    static func category(for title: String) -> String {
        let rules: [(String, String)] = [
            ("zoning", "Zoning"),
            ("school", "School Budget"),
            ("community preservation|\\bCPA\\b", "Community Preservation"),
            ("tax increment|economic development", "Economic Development"),
            ("borrow|debt|bond(?!s\\b)", "Capital Borrowing"),
            ("capital", "Capital Projects"),
            ("acqui|property|easement|land\\b|conservation", "Land & Property"),
            ("budget|appropriat|enterprise|revolving|stabilization|fund|transfer|salar", "Town Budget"),
            ("officers|reports", "Town Business"),
            ("M\\.G\\.L|bylaw|by-law|chapter", "Bylaws & Statutes"),
        ]
        for (pattern, name) in rules where RX.contains(pattern, in: title) { return name }
        return "General"
    }

    /// Clearly-labeled simulated community poll numbers, stable per article.
    static func simulatedTally(_ number: Int) -> SimulatedTally {
        SimulatedTally(yay: 280 + (number * 37) % 420, nay: 20 + (number * 53) % 140, abstain: nil)
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: date)
    }
}
