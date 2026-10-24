import Foundation

// Loads the bundled town data once. Everything downstream reads from here.
@Observable
final class DataStore {
    private(set) var data: TownData?

    var articles: [WarrantArticle] { data?.articles ?? [] }
    var meetings: [Meeting] { data?.meetings ?? [] }
    var historicalVotes: [HistoricalVote] { data?.historicalVotes ?? [] }

    func article(id: String) -> WarrantArticle? { articles.first { $0.id == id } }
    func history(id: String) -> HistoricalVote? { historicalVotes.first { $0.id == id } }
    func meeting(id: String) -> Meeting? { meetings.first { $0.id == id } }

    func load() {
        guard data == nil,
              let url = Bundle.main.url(forResource: "townhall_data", withExtension: "json"),
              let raw = try? Data(contentsOf: url) else { return }
        data = try? JSONDecoder().decode(TownData.self, from: raw)
    }
}
