import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(OSLog)
import OSLog
#endif

nonisolated enum LiveLog {
    static func log(_ message: String) {
        #if canImport(OSLog)
        Logger(subsystem: "com.townhalllive", category: "live").info("\(message, privacy: .public)")
        #else
        print("[live] \(message)")
        #endif
    }
}

// Scrapes the town's own public pages on-device: the Town Meeting page (links
// to the newest warrant booklet, results summary and session videos), the
// warrant and results PDFs (PDFKit), the town calendar RSS, and the Town TV
// YouTube channel feed. Every source is independent; whatever fails keeps the
// previous snapshot's value.
nonisolated struct TownScraper: Sendable {
    let sources: TownSources
    var session: URLSession = .shared

    @concurrent
    func refresh(previous: LiveSnapshot?) async -> LiveSnapshot {
        var snap = previous.flatMap { $0.sourceKey == sources.cacheKey ? $0 : nil }
            ?? LiveSnapshot(sourceKey: sources.cacheKey)
        var answered = false

        async let pageData = fetch(sources.townMeetingURL)
        async let calendarData = fetch(sources.calendarURL)
        async let videoData = fetch(sources.youtubeFeedURL)

        // Town Meeting page → meetings, warrant, results.
        if let html = await pageData.flatMap(Self.decodeHTML), let pageURL = sources.townMeetingURL {
            answered = true
            let meetings = TownMeetingPageParser.parse(html: html, pageURL: pageURL)
            LiveLog.log("town meeting page: \(meetings.count) meetings")
            if !meetings.isEmpty { snap.townMeetings = meetings }
        }

        let newest = snap.townMeetings.sorted { $0.year > $1.year }.first { $0.warrantURL != nil }
        if let meeting = newest, let warrantURL = meeting.warrantURL {
            if let cached = snap.warrant, cached.sourceURL == warrantURL, !cached.articles.isEmpty {
                LiveLog.log("warrant unchanged, reusing \(cached.articles.count) parsed articles")
            } else if let text = await pdfText(warrantURL) {
                answered = true
                let articles = WarrantParser.parse(text: text)
                LiveLog.log("warrant: \(articles.count) articles from \(text.count) chars")
                if !articles.isEmpty {
                    snap.warrant = LiveWarrant(meetingID: meeting.id, sourceURL: warrantURL,
                                               meetingDate: WarrantParser.meetingDate(in: text), articles: articles)
                }
            }
            if let resultsURL = meeting.resultsURL, let text = await pdfText(resultsURL) {
                answered = true
                let outcomes = ResultsParser.parse(text: text)
                LiveLog.log("results: \(outcomes.count) outcomes")
                if !outcomes.isEmpty {
                    snap.results = LiveResults(meetingID: meeting.id, sourceURL: resultsURL,
                                               meetingDates: ResultsParser.meetingDates(in: text), outcomes: outcomes)
                }
            }
        }

        // Calendar RSS → upcoming sessions (an empty list is a valid answer).
        if let data = await calendarData {
            answered = true
            snap.upcoming = FeedMapper.upcomingEvents(FeedParser.parse(data), filter: sources.calendarTitleFilter)
            LiveLog.log("calendar: \(snap.upcoming.count) upcoming")
        }

        // YouTube channel feed → recent meeting recordings.
        if let data = await videoData {
            let items = FeedParser.parse(data)
            if !items.isEmpty {
                answered = true
                snap.recordings = FeedMapper.recordings(items, filter: sources.recordingTitleFilter)
                LiveLog.log("youtube: \(snap.recordings.count) recordings")
            }
        }

        if answered { snap.fetchedAt = Date() }
        return snap
    }

    // MARK: Networking

    func fetch(_ url: URL?, timeout: TimeInterval = 30) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("TownHallLive/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                LiveLog.log("HTTP \(http.statusCode) for \(url.absoluteString)")
                return nil
            }
            return data.isEmpty ? nil : data
        } catch {
            LiveLog.log("fetch failed for \(url.absoluteString): \(error.localizedDescription)")
            return nil
        }
    }

    func pdfText(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString), let data = await fetch(url, timeout: 90) else { return nil }
        let text = Self.extractPDFText(data)
        if text == nil { LiveLog.log("not a readable PDF: \(urlString)") }
        return text
    }

    static func extractPDFText(_ data: Data) -> String? {
        #if canImport(PDFKit)
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let text = document.page(at: index)?.string { pages.append(text) }
        }
        let joined = pages.joined(separator: "\n")
        return joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : joined
        #else
        return String(data: data, encoding: .utf8)
        #endif
    }

    static func decodeHTML(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

// Caches-directory JSON for the last snapshot and the AI translation cache.
nonisolated enum LiveCache {
    static let snapshotFile = "live_snapshot.json"
    static let translationsFile = "plain_english_cache.json"

    static var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("TownHallLive", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = directory?.appendingPathComponent(name), let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            LiveLog.log("cache \(name) unreadable, ignoring: \(error.localizedDescription)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let url = directory?.appendingPathComponent(name) else { return }
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            LiveLog.log("cache \(name) write failed: \(error.localizedDescription)")
        }
    }
}
