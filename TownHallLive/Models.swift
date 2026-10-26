import Foundation

// Model layer. Value types, `nonisolated` so they cross isolation domains freely.
// The bundled JSON (`Resources/townhall_data.json`) is the offline fallback;
// live data from the town's own sources is merged over it. The bundle holds
// facts only (official text, outcomes, meetings): every plain-English
// explanation is written by the AI at runtime from the official text.
//
// Decoding is tolerant: unknown keys from older bundles or caches (e.g. the
// fields retired in earlier versions) are simply ignored.

/// The bundled JSON as shipped: no prewritten explanations.
nonisolated struct BundledTownData: Codable, Sendable {
    let town: TownInfo
    let meetings: [Meeting]
    let articles: [BundledArticle]
    let historicalVotes: [HistoricalVote]
}

/// A warrant article as bundled: official text and the recorded outcome only.
nonisolated struct BundledArticle: Codable, Sendable {
    let id: String
    let meetingID: String
    let number: Int
    let title: String
    let category: String
    let originalText: String
    let officialOutcome: OfficialOutcome?
    let relatedHistoricalVoteIDs: [String]
    /// Document the text was taken from, when known.
    var sourceURL: String? = nil
}

nonisolated struct TownData: Codable, Sendable {
    let town: TownInfo
    let meetings: [Meeting]
    let articles: [WarrantArticle]
    let historicalVotes: [HistoricalVote]
}

nonisolated struct TownInfo: Codable, Sendable {
    let name: String
    let state: String
}

nonisolated struct Meeting: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let date: String
    /// "latest" (newest Town Meeting), "recent", "past", "upcoming"
    let status: String
    let streamURL: String?
    /// nil = Town Meeting; "calendar" = upcoming event from the town calendar;
    /// "recording" = a recent Town TV meeting video.
    var kind: String? = nil
    /// Calendar event page (calendar items only).
    var link: String? = nil

    var isTownMeeting: Bool { kind == nil }

    /// Best-effort calendar date parsed from the display string
    /// ("Monday, May 4, 2026 · 7:00 PM" → May 4, 2026).
    var parsedDate: Date? { MeetingDate.parse(date) }
}

nonisolated enum MeetingDate {
    static func parse(_ text: String) -> Date? {
        let pattern = "(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else { return nil }
        let cleaned = String(text[r]).replacingOccurrences(of: "(st|nd|rd|th)", with: "", options: .regularExpression)
            .replacingOccurrences(of: ",", with: "")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d yyyy"
        return f.date(from: cleaned)
    }
}

nonisolated struct WarrantArticle: Codable, Sendable, Identifiable {
    let id: String
    let meetingID: String
    let number: Int
    let title: String
    let category: String
    let originalText: String
    let plainEnglish: PlainEnglish
    let financialImpact: FinancialImpact?
    let officialOutcome: OfficialOutcome?
    let relatedHistoricalVoteIDs: [String]
    /// "ai" = written through AIService from the official text,
    /// "excerpt" = taken straight from the warrant, not translated yet.
    var plainEnglishSource: String? = nil
    /// Document the text was scraped from (live data only).
    var sourceURL: String? = nil

    var isTranslated: Bool { plainEnglishSource == "ai" }
}

nonisolated struct PlainEnglish: Codable, Sendable, Equatable {
    let summary: String
    let keyTakeaways: [String]
    let votingYesMeans: String
    let votingNoMeans: String
}

nonisolated struct FinancialImpact: Codable, Sendable {
    let amount: String
    let explanation: String
}

nonisolated struct OfficialOutcome: Codable, Sendable {
    /// "passed" | "failed" | "no action" | "postponed"
    let result: String
    let tally: String?
    let sourceNote: String
}

nonisolated struct HistoricalVote: Codable, Sendable, Identifiable {
    let id: String
    let year: Int
    let meetingName: String
    let title: String
    let category: String
    let summary: String
    /// "passed" | "failed" | "no action" | "postponed"
    let outcome: String
    let tally: String
    /// Curated entries explain why the decision matters today; scraped ones leave it empty.
    let relevanceNote: String
    var articleNumber: Int? = nil
    /// Results document the entry was read from (live history only).
    var sourceURL: String? = nil
}

/// The user's own stance on an article — saved on this device only.
enum VoteChoice: String, CaseIterable, Identifiable {
    case yay = "Yay"
    case nay = "Nay"
    case abstain = "Abstain"
    var id: String { rawValue }
}
