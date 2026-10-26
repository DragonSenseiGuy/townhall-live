import Foundation

// Past Town Meeting decisions, read from the town website's document archive.
// CivicPlus "Archive Center" pages list every past warrant (one archive) and
// every results abstract (another archive) as "2024 Special Town Meeting -
// November 25, 2024" links to `Archive.aspx?ADID=<id>`, which serve PDFs.
// The results abstracts are parsed article by article into `HistoricalVote`s;
// when an abstract leaves titles out, the matching warrant fills them in.
// Pure parsing lives here; `HistoryScraper` does the networking.

nonisolated struct ArchiveEntry: Codable, Sendable, Equatable {
    /// CivicPlus document id (ADID).
    let id: String
    let title: String
    let url: String
    let year: Int
    let isSpecial: Bool
    /// "November 25, 2024" / "November" when the entry names one.
    let dateLabel: String?

    var meetingName: String { isSpecial ? "Special Town Meeting" : "Annual Town Meeting" }
}

nonisolated struct ParsedHistoricalArticle: Codable, Sendable, Equatable {
    let number: Int
    var title: String
    /// "passed" | "failed" | "no action" | "postponed"
    let result: String
    /// "243–26", "Unanimous", or nil
    let tally: String?
    let summary: String
}

nonisolated struct HistoryDocument: Codable, Sendable {
    let entry: ArchiveEntry
    var articles: [ParsedHistoricalArticle]
    /// True when the PDF had no extractable text or no recognizable votes.
    var unreadable: Bool
    var fetchedAt: Date
}

nonisolated struct HistoryCacheFile: Codable, Sendable {
    var sourceKey: String
    var listedAt: Date?
    var results: [ArchiveEntry] = []
    var warrants: [ArchiveEntry] = []
    var documents: [String: HistoryDocument] = [:]
}

// MARK: - Archive listing (HTML)

nonisolated enum ArchiveListParser {
    static func parse(html: String, pageURL: URL) -> [ArchiveEntry] {
        var out: [ArchiveEntry] = []
        var seen = Set<String>()
        let pattern = "<a\\s[^>]*?href\\s*=\\s*[\"']([^\"']*ADID=(\\d+)[^\"']*)[\"'][^>]*>([\\s\\S]*?)</a>"
        for m in RX.matches(pattern, in: html, [.caseInsensitive]) {
            guard let rawHref = RX.group(m, 1, in: html), let id = RX.group(m, 2, in: html),
                  let inner = RX.group(m, 3, in: html), !seen.contains(id) else { continue }
            let title = TextClean.stripTags(inner)
            guard let entry = entry(id: id, title: title, href: rawHref, base: pageURL) else { continue }
            seen.insert(id)
            out.append(entry)
        }
        return out
    }

    static func entry(id: String, title: String, href: String, base: URL) -> ArchiveEntry? {
        guard RX.contains("town\\s+meeting", in: title),
              let m = RX.first("\\b((?:19|20)\\d{2})\\b", in: title),
              let year = RX.group(m, 1, in: title).flatMap(Int.init),
              let url = URL(string: TextClean.decodeEntities(href), relativeTo: base)?.absoluteURL else { return nil }
        var dateLabel: String?
        if let d = RX.first("[-\\u2013\\u2014]\\s*(.+)$", in: title), let label = RX.group(d, 1, in: title) {
            let cleaned = TextClean.collapse(label.replacingOccurrences(of: "/", with: ""))
            if !cleaned.isEmpty { dateLabel = cleaned }
        }
        return ArchiveEntry(id: id, title: title, url: url.absoluteString, year: year,
                            isSpecial: RX.contains("\\bspecial\\b", in: title), dateLabel: dateLabel)
    }
}

// MARK: - Results abstract (PDF text)

nonisolated enum AbstractParser {
    static let headerPattern = "^[ \\t]*\\*?[ \\t]*Article[ \\t]+(\\d{1,3})(?:[ \\t]*(?:&|and)[ \\t]*\\d{1,3})?[ \\t]*[*#]?[ \\t]*[:.\\-\\u2013\\u2014]?[ \\t]*(.*)$"
    static let marker = "\\b(carries|carried|passes|passed|fails|failed|defeated|adopted|approved)\\b"
    static let markerContext = "\\b(motion|article|vote|consent|unanimous)"
    static let skip = "dissolve|adjourn|speaker|cut off debate|terminate debate|move the question|previous question|amend|reconsider|correct|practice|allow|line item|held|recess|attorney general|declared|bylaw|chapter|section|to see if"

    static let procedural = "dissolve|adjourn|recess|allow (?:non.?resident|speakers?)|cut off debate|terminate debate|move the question|previous question|reconsider"

    private struct Section { var title = ""; var body: [String] = [] }

    static func parse(text raw: String) -> [ParsedHistoricalArticle] {
        let text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{000C}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
        let lines = text.components(separatedBy: "\n")
        guard let headerRE = RX.make(headerPattern, [.caseInsensitive]) else { return [] }

        var headers: [(line: Int, number: Int, rest: String)] = []
        for (i, line) in lines.enumerated() {
            guard let m = headerRE.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let n = RX.group(m, 1, in: line).flatMap(Int.init), (1...99).contains(n) else { continue }
            let rest = (RX.group(m, 2, in: line) ?? "").trimmingCharacters(in: .whitespaces)
            // Prose mentions ("Article 6 at the 2022 Annual Town Meeting…") start lowercase.
            if !rest.isEmpty, RX.first("^[A-Z(\\u201C\"']", in: rest) == nil { continue }
            if RX.contains("\\.{4,}", in: rest) { continue }
            headers.append((i, n, rest))
        }

        var sections: [Int: Section] = [:]
        for (k, h) in headers.enumerated() {
            let end = k + 1 < headers.count ? headers[k + 1].line : lines.count
            let body = Array(lines[(h.line + 1)..<max(h.line + 1, end)])
            var section = sections[h.number] ?? Section()
            if section.title.isEmpty { section.title = title(rest: h.rest, body: body) }
            section.body += body
            sections[h.number] = section
        }

        var out: [ParsedHistoricalArticle] = []
        for number in sections.keys.sorted() {
            guard let section = sections[number], let (result, tally) = outcome(section.body) else { continue }
            out.append(ParsedHistoricalArticle(number: number, title: section.title, result: result,
                                               tally: tally, summary: summary(section.body)))
        }
        return out
    }

    static func cleanTitle(_ raw: String) -> String {
        var t = VoteRequirement.split(raw).title
        t = RX.replace("\\([^()]*$", in: t, with: "")
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .:-\u{2013}\u{2014}*#"))
        return t.count > 160 ? String(t.prefix(160)) + "…" : t
    }

    static func title(rest: String, body: [String]) -> String {
        var parts: [String] = []
        var dangling: String?
        let candidates = (rest.isEmpty ? [] : [rest]) + body.prefix(10)
        for line in candidates {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty {
                if !parts.isEmpty, parts.joined(separator: " ").split(separator: " ").count < 3 {
                    // A stray word extracted ahead of its line ("Project" before
                    // "Authorize Borrowing … Replacement") belongs at the end.
                    dangling = parts.joined(separator: " ")
                    parts = []
                    continue
                }
                if !parts.isEmpty { break }
                continue
            }
            if RX.first("^\\(.*\\)$", in: s) != nil || s == "*" || s == "#" { continue }
            if RX.first("^(To [a-z]|MOTION|Motion|Summary|Moved|Resolved|Held|Action Requested|We,? (?:the|urge)|[A-Z][a-z]+\\.? [A-Z][a-z\\-]+ moves)", in: s) != nil { break }
            parts.append(s)
            if parts.count >= 3 || s.hasSuffix(".") || s.hasSuffix(")") { break }
        }
        var t = parts.joined(separator: " ")
        if let dangling { t = (t + " " + dangling).trimmingCharacters(in: .whitespaces) }
        return cleanTitle(t)
    }

    static func outcome(_ body: [String]) -> (String, String?)? {
        var marks: [Int] = []
        for (i, line) in body.enumerated() {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.count <= 160, RX.contains(marker, in: s) else { continue }
            let shouting = s == s.uppercased()
            guard RX.contains(markerContext, in: s) || shouting else { continue }
            if RX.contains(skip, in: s) { continue }
            // A bare "MOTION CARRIES" answering a procedural motion on the line(s) above.
            let previous = body[max(0, i - 2)..<i].joined(separator: " ")
            let qualified = RX.contains("original|main|consent|article|remaining|items?\\b", in: s)
            if !qualified, RX.contains(procedural, in: previous) { continue }
            marks.append(i)
        }
        guard let i = marks.last else { return nil }
        let line = body[i].trimmingCharacters(in: .whitespaces)
        let lower = line.lowercased()
        var result = RX.contains("\\b(fails|failed|defeated|not approved|not carried)\\b", in: lower) ? "failed" : "passed"
        let start = marks.count > 1 ? marks[marks.count - 2] + 1 : 0
        let block = body[max(start, i - 12)...i].joined(separator: " ").lowercased()
        if result == "passed", RX.contains("no action", in: block) {
            result = "no action"
        } else if result == "passed", RX.contains("indefinitely postpone|postpone indefinitely|refer(red)? back", in: block) {
            result = "postponed"
        }

        var tally: String?
        // "MOTION CARRIES; 243-26", "ELECTRONIC VOTE 204-40"
        if line.rangeOfCharacter(from: .decimalDigits) != nil {
            let tail = line.contains(";") ? String(line[line.index(after: line.firstIndex(of: ";")!)...]) : line
            if let m = RX.first("(\\d{1,4})[ \\t]*(?:YES)?[ \\t]*[-\\u2013\\u2014][ \\t]*(\\d{1,4})", in: tail, [.caseInsensitive]),
               let y = RX.group(m, 1, in: tail), let n = RX.group(m, 2, in: tail) {
                tally = "\(y)\u{2013}\(n)"
            }
        }
        if tally == nil {
            // "IClicker - A Yes - 811 76% … E No - 261 24%", after or before the outcome line.
            var after: [String] = []
            for l in body[(i + 1)..<min(body.count, i + 6)] {
                if RX.contains(marker, in: l) { break }
                after.append(l)
            }
            let before = Array(body[max(start, i - 6)..<i])
            for window in [after.joined(separator: " "), before.joined(separator: " ")] {
                if let y = RX.first("\\bYes\\W{0,4}(\\d{1,4})\\b", in: window, [.caseInsensitive]),
                   let yes = RX.group(y, 1, in: window) {
                    let restStart = y.range.location + y.range.length
                    let rest = (window as NSString).substring(from: restStart)
                    if let n = RX.first("\\bNo\\W{0,4}(\\d{1,4})\\b", in: rest, [.caseInsensitive]),
                       let no = RX.group(n, 1, in: rest) {
                        tally = "\(yes)\u{2013}\(no)"
                        break
                    }
                }
            }
        }
        if tally == nil, lower.contains("unanimous") { tally = "Unanimous" }
        return (result, tally)
    }

    static func summary(_ body: [String]) -> String {
        let text = TextClean.collapse(body.joined(separator: " "))
        guard let m = RX.first("To see if the Town (?:will|shall) (?:vote to )?([^.]{20,400}?)(?:,? or (?:to )?(?:take|act)|\\.)", in: text),
              let s = RX.group(m, 1, in: text)?.trimmingCharacters(in: .whitespaces), let first = s.first else { return "" }
        return String(first).uppercased() + s.dropFirst() + "."
    }

    /// True when enough parsed articles lack a usable title that the warrant
    /// should be consulted.
    static func needsWarrantTitles(_ articles: [ParsedHistoricalArticle]) -> Bool {
        guard !articles.isEmpty else { return false }
        let missing = articles.filter { $0.title.count < 4 }.count
        return missing * 4 >= articles.count || missing >= 5
    }
}

// MARK: - Mapping to the app model

nonisolated enum HistoryMapper {
    static func votes(from document: HistoryDocument) -> [HistoricalVote] {
        let entry = document.entry
        var meeting = entry.meetingName
        if let label = entry.dateLabel { meeting += " · \(label)" }
        return document.articles.compactMap { a in
            let title = a.title.count >= 4 ? a.title : "Article \(a.number)"
            return HistoricalVote(
                id: "hx-\(entry.id)-\(a.number)",
                year: entry.year,
                meetingName: meeting,
                title: title,
                category: LiveMerger.category(for: title),
                summary: a.summary,
                outcome: a.result,
                tally: a.tally ?? "",
                relevanceNote: "",
                articleNumber: a.number,
                sourceURL: entry.url
            )
        }
    }

    /// Curated entries win over scraped rows for the same meeting + article.
    static func merge(curated: [HistoricalVote], scraped: [HistoricalVote]) -> [HistoricalVote] {
        func key(_ v: HistoricalVote) -> String? {
            guard let n = v.articleNumber else { return nil }
            let kind = v.meetingName.lowercased().contains("special") ? "stm" : "atm"
            return "\(v.year)-\(kind)-\(n)"
        }
        let curatedKeys = Set(curated.compactMap(key))
        return curated + scraped.filter { v in key(v).map { !curatedKeys.contains($0) } ?? true }
    }
}
