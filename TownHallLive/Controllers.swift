import Foundation

// The user's own Yay / Nay / Abstain stance per article. Purely personal:
// saved in UserDefaults on this device, never sent anywhere, and shown next to
// the real official outcome — there are no community numbers.
@Observable
final class StanceStore {
    private static let key = "stances.v1"
    private(set) var stances: [String: VoteChoice] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        stances = raw.compactMapValues(VoteChoice.init(rawValue:))
    }

    func stance(for articleID: String) -> VoteChoice? { stances[articleID] }

    /// Tapping the current choice again clears it.
    func toggle(_ choice: VoteChoice, for articleID: String) {
        if stances[articleID] == choice {
            stances[articleID] = nil
        } else {
            stances[articleID] = choice
        }
        defaults.set(stances.mapValues(\.rawValue), forKey: Self.key)
    }
}
