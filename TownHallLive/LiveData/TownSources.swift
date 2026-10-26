import Foundation

// Where live data comes from. Real values live in the gitignored
// `Resources/TownSources.plist` (copy `TownSources.example.plist`); the town
// website base URL and YouTube channel ID can be overridden in Settings.
// Missing or placeholder config → the app runs on bundled data only.
nonisolated struct TownSources: Sendable, Equatable {
    var townName: String?
    var state: String?
    /// e.g. https://www.example-town.gov (no trailing slash needed)
    var websiteBaseURL: URL?
    /// Page listing each Town Meeting's warrant, results and videos.
    var townMeetingPath: String
    /// CivicPlus calendar RSS (path or absolute URL).
    var calendarRSSPath: String?
    /// Regex a calendar item's title must match to show as an upcoming session.
    var calendarTitleFilter: String
    /// Town TV YouTube channel (UC…).
    var youtubeChannelID: String?
    /// Regex a video title must match to count as a meeting recording.
    var recordingTitleFilter: String
    /// Document archive listing past Town Meeting results abstracts (CivicPlus Archive.aspx?AMID=…).
    var resultsArchivePath: String? = nil
    /// Document archive listing past warrants (used for titles the results leave out).
    var warrantsArchivePath: String? = nil
    /// Oldest year the History tab reads from the archive.
    var historyFromYear: Int = 2018

    /// Changes when the configured sources change, so stale caches are dropped.
    var cacheKey: String {
        [websiteBaseURL?.absoluteString ?? "", townMeetingPath, calendarRSSPath ?? "", youtubeChannelID ?? ""].joined(separator: "|")
    }

    var isConfigured: Bool { websiteBaseURL != nil || youtubeChannelID != nil }

    func url(_ pathOrURL: String) -> URL? {
        if pathOrURL.lowercased().hasPrefix("http") { return URL(string: pathOrURL) }
        guard let base = websiteBaseURL else { return nil }
        return URL(string: pathOrURL, relativeTo: base)?.absoluteURL
    }

    var townMeetingURL: URL? { websiteBaseURL == nil ? nil : url(townMeetingPath) }
    var calendarURL: URL? { calendarRSSPath.flatMap { websiteBaseURL == nil && !$0.lowercased().hasPrefix("http") ? nil : url($0) } }
    var resultsArchiveURL: URL? { websiteBaseURL == nil ? nil : resultsArchivePath.flatMap(url) }
    var warrantsArchiveURL: URL? { websiteBaseURL == nil ? nil : warrantsArchivePath.flatMap(url) }
    var historyKey: String {
        [websiteBaseURL?.absoluteString ?? "", resultsArchivePath ?? "", warrantsArchivePath ?? "", String(historyFromYear)].joined(separator: "|")
    }

    var youtubeFeedURL: URL? {
        youtubeChannelID.flatMap { URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\($0)") }
    }

    static let websiteOverrideKey = "live.websiteBaseURL"
    static let youtubeOverrideKey = "live.youtubeChannelID"

    /// Bundle plist merged with Settings overrides.
    static func current(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> TownSources {
        var plist: [String: Any] = [:]
        if let url = bundle.url(forResource: "TownSources", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            plist = dict
        }
        func string(_ key: String) -> String? {
            let value = (plist[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        func override(_ key: String) -> String? {
            let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }

        let website = (override(websiteOverrideKey) ?? string("websiteBaseURL")).flatMap(validWebsite)
        let channel = (override(youtubeOverrideKey) ?? string("youtubeChannelID")).flatMap(validChannel)
        return TownSources(
            townName: string("townName").flatMap { isPlaceholder($0) ? nil : $0 },
            state: string("state"),
            websiteBaseURL: website,
            townMeetingPath: string("townMeetingPath") ?? "/townmeeting",
            calendarRSSPath: string("calendarRSSPath"),
            calendarTitleFilter: string("calendarTitleFilter") ?? "Town Meeting",
            youtubeChannelID: channel,
            recordingTitleFilter: string("recordingTitleFilter") ?? "Meeting",
            resultsArchivePath: string("resultsArchivePath").flatMap { isPlaceholder($0) ? nil : $0 },
            warrantsArchivePath: string("warrantsArchivePath").flatMap { isPlaceholder($0) ? nil : $0 },
            historyFromYear: (plist["historyFromYear"] as? Int)
                ?? string("historyFromYear").flatMap(Int.init) ?? 2018
        )
    }

    static func isPlaceholder(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("example") || lower.contains("xxxx") || lower.contains("your-")
    }

    static func validWebsite(_ raw: String) -> URL? {
        var value = raw
        if !value.lowercased().hasPrefix("http") { value = "https://" + value }
        while value.hasSuffix("/") { value.removeLast() }
        guard !isPlaceholder(value), let url = URL(string: value), url.host != nil else { return nil }
        return url
    }

    static func validChannel(_ raw: String) -> String? {
        guard !isPlaceholder(raw), raw.hasPrefix("UC"), raw.count >= 20 else { return nil }
        return raw
    }
}
