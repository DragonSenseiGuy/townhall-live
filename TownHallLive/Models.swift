// Model layer. Value types, `nonisolated` so they cross isolation domains freely.
// One bundled JSON file (`Resources/townhall_data.json`) feeds the whole app.

nonisolated struct TownData: Codable, Sendable {
    let town: TownInfo
    let meetings: [Meeting]
    let articles: [WarrantArticle]
    let historicalVotes: [HistoricalVote]
    let demoSession: [DemoStep]
}

nonisolated struct TownInfo: Codable, Sendable {
    let name: String
    let state: String
}

nonisolated struct Meeting: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let date: String
    /// "live" (simulated demo), "recent", "past"
    let status: String
    let streamURL: String?
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
    let simulatedTally: SimulatedTally
    let relatedHistoricalVoteIDs: [String]

    var displayNumber: String { "Article \(number)" }
}

nonisolated struct PlainEnglish: Codable, Sendable {
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
    /// "passed" | "failed" | "postponed"
    let result: String
    let tally: String?
    let sourceNote: String
}

nonisolated struct SimulatedTally: Codable, Sendable {
    let yay: Int
    let nay: Int
    let abstain: Int?
}

nonisolated struct HistoricalVote: Codable, Sendable, Identifiable {
    let id: String
    let year: Int
    let meetingName: String
    let title: String
    let category: String
    let summary: String
    /// "passed" | "failed"
    let outcome: String
    let tally: String
    let relevanceNote: String
}

nonisolated struct DemoStep: Codable, Sendable, Identifiable {
    let id: Int
    let articleID: String
    let headline: String
    let caption: String
}

enum VoteChoice: String, CaseIterable, Identifiable {
    case yay = "Yay"
    case nay = "Nay"
    case abstain = "Abstain"
    var id: String { rawValue }
}
