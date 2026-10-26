import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// Pure text/HTML/XML parsing for the live town data. No networking, no UI:
// every function takes a string (or bytes) and returns plain values, so the
// rules can be exercised against real documents in isolation.
//
// Tuned against a CivicPlus/CivicEngage town site (Town Meeting page, warrant
// booklet PDF, results summary PDF, calendar RSS) and YouTube channel feeds.

// MARK: - Parsed shapes

nonisolated struct TownMeetingLinks: Codable, Sendable, Equatable {
    /// "atm-2026", "stm-2024" — same ids the bundled data uses.
    let id: String
    let title: String
    let year: Int
    let warrantURL: String?
    let resultsURL: String?
    let videoURLs: [String]
}

nonisolated struct ParsedArticle: Codable, Sendable, Equatable {
    let number: Int
    let title: String
    /// e.g. "majority vote", "two-thirds majority vote"
    let voteRequirement: String?
    /// Verbatim "To see if the Town will …" text.
    let legalText: String
    /// The booklet's own explanatory "Summary" paragraph, when present.
    let bookletSummary: String?
    let recommendations: String?
    /// Dollar figures in the legal text, in order of appearance.
    let amounts: [String]
}

nonisolated struct ParsedOutcome: Codable, Sendable, Equatable {
    let number: Int
    /// "passed" | "failed" | "no action" | "postponed"
    let result: String
    /// Outcome as printed, e.g. "Approved", "No Action Taken".
    let label: String
    /// "312–41" when the sheet prints a count.
    let tally: String?
}

nonisolated struct FeedItem: Sendable, Equatable {
    var title = ""
    var link = ""
    var published = ""
    var summary = ""
    /// Child elements by local name (namespace prefix stripped).
    var fields: [String: String] = [:]
}

// MARK: - Regex helpers

nonisolated enum RX {
    static func make(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    static func matches(_ pattern: String, in text: String, _ options: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        guard let re = make(pattern, options) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func first(_ pattern: String, in text: String, _ options: NSRegularExpression.Options = []) -> NSTextCheckingResult? {
        guard let re = make(pattern, options) else { return nil }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let r = match.range(at: index)
        guard r.location != NSNotFound, let range = Range(r, in: text) else { return nil }
        return String(text[range])
    }

    static func replace(_ pattern: String, in text: String, with template: String, _ options: NSRegularExpression.Options = []) -> String {
        guard let re = make(pattern, options) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    static func contains(_ pattern: String, in text: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> Bool {
        first(pattern, in: text, options) != nil
    }
}

nonisolated enum TextClean {
    static func collapse(_ s: String) -> String {
        RX.replace("\\s+", in: s, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&ndash;", "\u{2013}"), ("&mdash;", "\u{2014}"), ("&lt;", "<"), ("&gt;", ">"),
        ]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric entities.
        for m in RX.matches("&#(x?[0-9A-Fa-f]+);", in: out).reversed() {
            guard let body = RX.group(m, 1, in: out), let range = Range(m.range, in: out) else { continue }
            let value = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            if let value, let scalar = Unicode.Scalar(value) {
                out.replaceSubrange(range, with: String(Character(scalar)))
            }
        }
        return out
    }

    static func stripTags(_ html: String) -> String {
        collapse(decodeEntities(RX.replace("<[^>]+>", in: html, with: " ")))
    }

    /// First `count` sentences, capped at `maxLength` characters.
    static func sentences(_ s: String, count: Int, maxLength: Int = 360) -> String {
        let text = collapse(s)
        var out = ""
        var taken = 0
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if (ch == "." || ch == "?" || ch == "!") && next == " " {
                // Skip common abbreviations ("M.G.L.", "St.", "No.").
                let tail = current.suffix(5)
                if tail.hasSuffix("St.") || tail.hasSuffix("No.") || tail.hasSuffix(" c.") || tail.hasSuffix("G.L.") || tail.hasSuffix(" ss.") {
                    continue
                }
                out += current
                current = ""
                taken += 1
                if taken >= count { break }
            }
        }
        if taken < count { out += current }
        out = collapse(out)
        if out.count > maxLength {
            out = String(out.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return out
    }

    static func dollarValue(_ amount: String) -> Double {
        let lower = amount.lowercased()
        let digits = amount.filter { $0.isNumber || $0 == "." }
        var value = Double(digits) ?? 0
        if lower.contains("million") { value *= 1_000_000 }
        if lower.contains("billion") { value *= 1_000_000_000 }
        return value
    }
}

// MARK: - Town Meeting page (HTML)

nonisolated enum TownMeetingPageParser {
    /// Splits the Town Meeting page into one block per "<year> Annual/Special
    /// Town Meeting" heading and classifies the links inside each block.
    /// Newest first, as the page lists them.
    static func parse(html: String, pageURL: URL) -> [TownMeetingLinks] {
        let headings = RX.matches("<h[1-6][^>]*>([\\s\\S]*?)</h[1-6]>", in: html, [.caseInsensitive])
        var out: [TownMeetingLinks] = []
        var seen = Set<String>()
        for (index, heading) in headings.enumerated() {
            guard let inner = RX.group(heading, 1, in: html) else { continue }
            let text = TextClean.stripTags(inner)
            guard let (year, special) = meetingKind(text) else { continue }
            let start = heading.range.location + heading.range.length
            let end = index + 1 < headings.count ? headings[index + 1].range.location : (html as NSString).length
            guard end > start else { continue }
            let block = (html as NSString).substring(with: NSRange(location: start, length: end - start))
            let links = anchors(in: block, base: pageURL)
            let meeting = classify(links: links, year: year, special: special, seen: &seen)
            if meeting.warrantURL != nil || meeting.resultsURL != nil || !meeting.videoURLs.isEmpty {
                out.append(meeting)
            }
        }
        if out.isEmpty {
            // No per-meeting headings: fall back to the first warrant / results
            // documents anywhere on the page.
            let links = anchors(in: html, base: pageURL)
            let yearText = links.first { isWarrant($0.text, $0.href) }.map { "\($0.text) \($0.href)" } ?? ""
            let year = RX.first("\\b(20\\d{2})\\b", in: yearText).flatMap { RX.group($0, 1, in: yearText) }.flatMap(Int.init)
                ?? Calendar(identifier: .gregorian).component(.year, from: Date())
            let meeting = classify(links: links, year: year, special: false, seen: &seen)
            if meeting.warrantURL != nil || meeting.resultsURL != nil { out.append(meeting) }
        }
        return out
    }

    static func meetingKind(_ text: String) -> (Int, Bool)? {
        guard RX.contains("\\b(annual|special)\\b[^<]{0,40}town\\s+meeting", in: text),
              let m = RX.first("\\b((?:19|20)\\d{2})\\b", in: text),
              let year = RX.group(m, 1, in: text).flatMap(Int.init) else { return nil }
        return (year, RX.contains("\\bspecial\\b", in: text))
    }

    struct Anchor { let href: String; let text: String }

    static func anchors(in html: String, base: URL) -> [Anchor] {
        RX.matches("<a\\s[^>]*?href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>", in: html, [.caseInsensitive]).compactMap { m in
            guard let rawHref = RX.group(m, 1, in: html), let inner = RX.group(m, 2, in: html) else { return nil }
            let text = TextClean.stripTags(inner)
            // Empty anchors are editor leftovers (often pointing at another year).
            guard !text.isEmpty else { return nil }
            let href = TextClean.decodeEntities(rawHref)
            guard let url = URL(string: href, relativeTo: base)?.absoluteURL else { return nil }
            return Anchor(href: url.absoluteString, text: text)
        }
    }

    static func isWarrant(_ text: String, _ href: String) -> Bool {
        let s = "\(text) \(href)"
        return RX.contains("warrant", in: s) && !RX.contains("procedure|guide|view all|most recent|rules", in: s)
            && !isVideo(href)
    }

    static func isResults(_ text: String, _ href: String) -> Bool {
        let s = "\(text) \(href)"
        return RX.contains("summary|results|actions|abstract|votes taken", in: s) && !RX.contains("view all|most recent", in: s)
            && !isVideo(href)
    }

    static func isVideo(_ href: String) -> Bool {
        RX.contains("youtu\\.?be|vimeo\\.com", in: href)
    }

    private static func classify(links: [Anchor], year: Int, special: Bool, seen: inout Set<String>) -> TownMeetingLinks {
        var warrant: String?
        var results: String?
        var videos: [String] = []
        for link in links {
            if isVideo(link.href) {
                if !videos.contains(link.href) { videos.append(link.href) }
            } else if results == nil, isResults(link.text, link.href) {
                results = link.href
            } else if warrant == nil, isWarrant(link.text, link.href) {
                warrant = link.href
            }
        }
        var id = "\(special ? "stm" : "atm")-\(year)"
        var suffix = 2
        while seen.contains(id) {
            id = "\(special ? "stm" : "atm")-\(year)-\(suffix)"
            suffix += 1
        }
        seen.insert(id)
        return TownMeetingLinks(
            id: id,
            title: special ? "Special Town Meeting" : "Annual Town Meeting",
            year: year,
            warrantURL: warrant,
            resultsURL: results,
            videoURLs: videos
        )
    }
}

// MARK: - Warrant booklet (PDF text)

nonisolated enum WarrantParser {
    static let amountPattern = "\\$\\s?\\d{1,3}(?:,\\d{3})+(?:\\.\\d{2})?(?:\\s*(?:million|billion))?|\\$\\s?\\d+(?:\\.\\d+)?\\s*(?:million|billion)|\\$\\s?\\d{4,}(?:\\.\\d{2})?"

    /// Normalizes PDF text: unifies line breaks, drops running page headers
    /// ("… Warrant … Page 27") wherever they landed.
    static func normalize(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{FB01}", with: "fi")
            .replacingOccurrences(of: "\u{FB02}", with: "fl")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{000C}", with: "\n")
        // Most common "<prefix> Page N" line is the running header.
        var counts: [String: Int] = [:]
        for m in RX.matches("(?m)^[ \\t]*(.{10,140}?)[ \\t]+Page[ \\t]+\\d{1,3}[ \\t]*$", in: text) {
            if let prefix = RX.group(m, 1, in: text) { counts[prefix, default: 0] += 1 }
        }
        if let (prefix, n) = counts.max(by: { $0.value < $1.value }), n >= 3 {
            let escaped = NSRegularExpression.escapedPattern(for: prefix)
            text = RX.replace("[ \\t]*\(escaped)[ \\t]+Page[ \\t]+\\d{1,3}[ \\t]*\\n?", in: text, with: "\n")
        }
        text = RX.replace("(?m)^[ \\t]*Page[ \\t]+\\d{1,3}([ \\t]+of[ \\t]+\\d{1,3})?[ \\t]*$\\n?", in: text, with: "")
        return text
    }

    static func parse(text raw: String) -> [ParsedArticle] {
        let text = normalize(raw)
        let ns = text as NSString
        let headerPattern = "(?mi)^[ \\t]*\\*?[ \\t]*Article[ \\t]+(\\d{1,3})(?:[ \\t]*(?:&|and)[ \\t]*\\d{1,3})?[ \\t]*[:.\\u2013\\u2014-]?[ \\t]*(.*)$"
        let headers = RX.matches(headerPattern, in: text)

        struct Candidate { let number: Int; let headerStart: Int; let bodyStart: Int; let titleEnd: Int; let titleText: String }
        var accepted: [Candidate] = []
        for h in headers {
            guard let number = RX.group(h, 1, in: text).flatMap(Int.init) else { continue }
            let headerEnd = h.range.location + h.range.length
            // The legal text must open ("To see if…", "To choose…") within a few
            // lines of the header; table-of-contents lines and prose mentions don't.
            let windowLen = min(500, ns.length - headerEnd)
            guard windowLen > 0 else { continue }
            let window = ns.substring(with: NSRange(location: headerEnd, length: windowLen))
            guard let open = RX.first("\\n[ \\t]*(To[ \\t]+[a-z])", in: window) else { continue }
            let between = (window as NSString).substring(to: open.range.location)
            // Title continuation lines only — no more than three.
            if between.components(separatedBy: "\n").filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count > 3 { continue }
            if RX.contains("\\.{4,}|…{2,}", in: RX.group(h, 2, in: text) ?? "") { continue }
            let titleText = (RX.group(h, 2, in: text) ?? "") + " " + between
            let bodyStart = headerEnd + open.range.location + 1
            accepted.append(Candidate(number: number, headerStart: h.range.location, bodyStart: bodyStart, titleEnd: bodyStart, titleText: titleText))
        }

        var out: [ParsedArticle] = []
        var seen = Set<Int>()
        for (i, c) in accepted.enumerated() {
            guard !seen.contains(c.number) else { continue }
            let end = i + 1 < accepted.count ? accepted[i + 1].headerStart : ns.length
            guard end > c.bodyStart else { continue }
            let body = ns.substring(with: NSRange(location: c.bodyStart, length: end - c.bodyStart))
            let (title, vote) = cleanTitle(c.titleText)
            guard !title.isEmpty, !RX.contains("placeholder|not used", in: title) else { continue }
            seen.insert(c.number)
            out.append(article(number: c.number, title: title, vote: vote, body: body))
        }
        return out.sorted { $0.number < $1.number }
    }

    static func cleanTitle(_ raw: String) -> (String, String?) {
        var title = TextClean.collapse(raw)
        title = RX.replace("^[*\\s]+", in: title, with: "")
        title = RX.replace("[.…\\s]+\\d{0,3}$", in: title, with: "")
        var vote: String?
        if let m = RX.first("\\(([^()]*(?:vote|majority)[^()]*)\\)\\s*$", in: title, [.caseInsensitive]),
           let range = Range(m.range, in: title) {
            vote = RX.group(m, 1, in: title).map(TextClean.collapse)
            title = String(title[..<range.lowerBound])
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " .:-–—*…"))
        return (title, vote)
    }

    static func article(number: Int, title: String, vote: String?, body: String) -> ParsedArticle {
        let ns = body as NSString
        // Legal text ends at the boilerplate closing clause.
        let closing = "or\\s+(?:to\\s+)?(?:take|act\\s+on|act)\\s+(?:any\\s+)?(?:other\\s+)?(?:action|thing|anything)\\s+(?:relative|in\\s+relation|related)\\s+(?:thereto|to\\s+it)\\s*[.;,]?"
        var legalEnd = ns.length
        if let m = RX.first(closing, in: body, [.caseInsensitive]) {
            legalEnd = m.range.location + m.range.length
        } else if let m = RX.first("(?m)^[ \\t]*(Summary|Explanation|Recommendations?|Direct Inquiries)\\b", in: body) {
            legalEnd = m.range.location
        }
        var legal = TextClean.collapse(ns.substring(to: legalEnd))
        if legal.count > 8000 { legal = String(legal.prefix(8000)) + "…" }

        let rest = ns.substring(from: legalEnd)
        var summary: String?
        if let m = RX.first("(?m)^[ \\t]*(?:Summary|Explanation)[ \\t]*:?[ \\t]*\\n?", in: rest) {
            let after = (rest as NSString).substring(from: m.range.location + m.range.length)
            let stop = RX.first("(?m)(Direct Inquiries|Recommendations?\\s*:|^[ \\t]*Select Board (?:recommends|position)|^[ \\t]*Finance Committee (?:recommends|position))", in: after)
            let chunk = stop.map { (after as NSString).substring(to: $0.range.location) } ?? String(after.prefix(2500))
            let s = TextClean.collapse(chunk)
            if s.count > 20 { summary = s.count > 2500 ? String(s.prefix(2500)) + "…" : s }
        }

        var recommendations: String?
        if let m = RX.first("Recommendations?\\s*:\\s*([^\\n]+(?:\\n(?![ \\t]*(?:\\*?[ \\t]*Article|Summary|Direct))[^\\n]+)?)", in: rest, [.caseInsensitive]),
           let r = RX.group(m, 1, in: rest) {
            recommendations = TextClean.collapse(r)
        }

        let amounts = RX.matches(amountPattern, in: legal, [.caseInsensitive]).compactMap { RX.group($0, 0, in: legal) }
            .map { TextClean.collapse($0.replacingOccurrences(of: "$ ", with: "$")) }

        return ParsedArticle(
            number: number,
            title: title,
            voteRequirement: vote,
            legalText: legal,
            bookletSummary: summary,
            recommendations: recommendations,
            amounts: amounts
        )
    }

    /// "Monday, May 4, 2026 · 7:00 PM" for the Town Meeting session, if printed.
    static func meetingDate(in raw: String) -> String? {
        let text = String(raw.prefix(30000))
        let weekday = "(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)"
        let month = "(?:January|February|March|April|May|June|July|August|September|October|November|December)"
        let pattern = "Town\\s+Meeting[\\s\\S]{0,60}?(\(weekday)),?\\s+(\(month))\\s+(\\d{1,2}),?\\s+(\\d{4})(?:[\\s\\S]{0,12}?(\\d{1,2}:\\d{2}\\s*[AaPp]\\.?[Mm]\\.?))?"
        // Skip spans that run into an election date ("Town Meeting … Town Election Tuesday …").
        guard let m = RX.matches(pattern, in: text).first(where: { match in
            RX.group(match, 0, in: text).map { !RX.contains("election", in: $0) } ?? false
        }) else { return nil }
        guard let wd = RX.group(m, 1, in: text), let mo = RX.group(m, 2, in: text),
              let d = RX.group(m, 3, in: text), let y = RX.group(m, 4, in: text) else { return nil }
        var out = "\(wd), \(mo) \(d), \(y)"
        if let t = RX.group(m, 5, in: text) {
            let time = RX.replace("\\s*([AaPp])\\.?[Mm]\\.?", in: t, with: " $1M").uppercased()
            out += " · \(time)"
        }
        return out
    }
}

// MARK: - Results summary (PDF text)

nonisolated enum ResultsParser {
    static let outcomeWords = "No Action Taken|No Action|Indefinitely Postponed|Postponed Indefinitely|Not Approved|Not Adopted|Not Passed|Not Carried|Withdrawn|Passed Over|Referred(?: Back)?|Tabled|Postponed|Defeated|Failed|Approved|Adopted|Passed|Carried|Accepted"
    static let tallyPattern = "(?:[ \\t]*\\(?[ \\t]*(\\d{1,4})[ \\t]*(?:-|\\u2013|\\u2014|to)[ \\t]*(\\d{1,4})[ \\t]*\\)?)?"

    static func parse(text raw: String) -> [ParsedOutcome] {
        let text = WarrantParser.normalize(raw)
        // Row mode: "7 <title, possibly wrapped> Approved [312-41]".
        let row = "(?m)^[ \\t]*\\*?[ \\t]*(\\d{1,3})[.):]?[ \\t]*\\n?[ \\t]*((?:(?!\\n[ \\t]*\\d{1,3}[ \\t\\n])[\\s\\S])+?)[ \\t]+(\(outcomeWords))\(tallyPattern)[ \\t]*$"
        var byNumber: [Int: ParsedOutcome] = [:]
        for m in RX.matches(row, in: text, [.caseInsensitive]) {
            guard let n = RX.group(m, 1, in: text).flatMap(Int.init), let label = RX.group(m, 3, in: text) else { continue }
            if byNumber[n] == nil {
                byNumber[n] = outcome(number: n, label: label, yes: RX.group(m, 4, in: text), no: RX.group(m, 5, in: text))
            }
        }
        // Column mode: numbers and outcomes extracted as separate runs.
        let numbers = RX.matches("(?m)^[ \\t]*(\\d{1,3})[ \\t]*$", in: text).compactMap { RX.group($0, 1, in: text).flatMap(Int.init) }
        let outcomes = RX.matches("(?m)^[ \\t]*(\(outcomeWords))\(tallyPattern)[ \\t]*$", in: text, [.caseInsensitive])
        if byNumber.count < max(3, outcomes.count / 2) {
            var sequence: [Int] = []
            for n in numbers where n == (sequence.last ?? 0) + 1 { sequence.append(n) }
            if !sequence.isEmpty, sequence.count == outcomes.count {
                for (n, m) in zip(sequence, outcomes) where byNumber[n] == nil {
                    guard let label = RX.group(m, 1, in: text) else { continue }
                    byNumber[n] = outcome(number: n, label: label, yes: RX.group(m, 2, in: text), no: RX.group(m, 3, in: text))
                }
            }
        }
        return byNumber.values.sorted { $0.number < $1.number }
    }

    static func outcome(number: Int, label raw: String, yes: String?, no: String?) -> ParsedOutcome {
        let label = TextClean.collapse(raw).capitalized
        let lower = label.lowercased()
        let result: String
        if lower.hasPrefix("not ") || lower == "defeated" || lower == "failed" {
            result = "failed"
        } else if lower.contains("no action") || lower == "withdrawn" || lower == "passed over" {
            result = "no action"
        } else if lower.contains("postpone") || lower.hasPrefix("referred") || lower == "tabled" {
            result = "postponed"
        } else {
            result = "passed"
        }
        var tally: String?
        if let yes, let no { tally = "\(yes)\u{2013}\(no)" }
        return ParsedOutcome(number: number, result: result, label: label, tally: tally)
    }

    /// "(May 4th and 5th 2026)" → "May 4th and 5th 2026"
    static func meetingDates(in raw: String) -> String? {
        let text = String(raw.prefix(3000))
        let month = "(?:January|February|March|April|May|June|July|August|September|October|November|December)"
        guard let m = RX.first("(\(month)\\s+\\d{1,2}(?:st|nd|rd|th)?(?:\\s*(?:and|&|-|\\u2013)\\s*\\d{1,2}(?:st|nd|rd|th)?)?,?\\s*\\d{4})", in: text) else { return nil }
        return RX.group(m, 1, in: text).map(TextClean.collapse)
    }
}

// MARK: - RSS / Atom

nonisolated final class FeedParser: NSObject, XMLParserDelegate {
    private var items: [FeedItem] = []
    private var current: FeedItem?
    private var buffer = ""

    static func parse(_ data: Data) -> [FeedItem] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return delegate.items
    }

    private static func localName(_ qName: String) -> String {
        qName.split(separator: ":").last.map(String.init) ?? qName
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = Self.localName(elementName)
        if name == "item" || name == "entry" {
            current = FeedItem()
        } else if current != nil, name == "link", let href = attributeDict["href"] {
            let rel = attributeDict["rel"] ?? "alternate"
            if rel == "alternate" || (current?.link.isEmpty ?? false) { current?.link = href }
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        buffer += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = Self.localName(elementName)
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { buffer = "" }
        if name == "item" || name == "entry" {
            if let item = current { items.append(item) }
            current = nil
            return
        }
        guard current != nil else { return }
        switch name {
        case "title": current?.title = TextClean.decodeEntities(value)
        case "link": if !value.isEmpty { current?.link = value }
        case "pubDate", "published": current?.published = value
        case "description", "summary": current?.summary = value
        default: break
        }
        if !value.isEmpty { current?.fields[name] = value }
    }
}

// MARK: - Calendar & recordings

nonisolated struct CalendarEvent: Codable, Sendable, Equatable {
    let id: String
    let title: String
    let date: Date
    let dateText: String
    let link: String
}

nonisolated struct Recording: Codable, Sendable, Equatable {
    let videoID: String
    let title: String
    let url: String
    let published: Date?
}

nonisolated enum FeedMapper {
    /// Upcoming events from a CivicPlus calendar RSS whose title matches `filter`.
    static func upcomingEvents(_ items: [FeedItem], filter: String, now: Date = Date()) -> [CalendarEvent] {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "MMMM d, yyyy"
        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US_POSIX")
        display.dateFormat = "EEEE, MMMM d, yyyy"
        let startOfToday = Calendar(identifier: .gregorian).startOfDay(for: now)
        var out: [CalendarEvent] = []
        for item in items {
            guard filter.isEmpty || RX.contains(filter, in: item.title) else { continue }
            let datesField = item.fields["EventDates"] ?? TextClean.stripTags(TextClean.decodeEntities(item.summary))
            guard let m = RX.first("([A-Z][a-z]+\\s+\\d{1,2},\\s+\\d{4})", in: datesField),
                  let first = RX.group(m, 1, in: datesField),
                  let date = parser.date(from: first), date >= startOfToday else { continue }
            var text = display.string(from: date)
            if let times = item.fields["EventTimes"], let t = RX.first("(\\d{1,2}:\\d{2}\\s*[AP]M)", in: times, [.caseInsensitive]),
               let start = RX.group(t, 1, in: times) {
                text += " · " + RX.replace("^0", in: start, with: "")
            }
            let id = RX.first("EID=(\\d+)", in: item.link).flatMap { RX.group($0, 1, in: item.link) } ?? String(item.title.hashValue)
            out.append(CalendarEvent(id: "cal-\(id)", title: item.title, date: date, dateText: text, link: item.link))
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Recent videos from a YouTube channel Atom feed whose title matches `filter`.
    static func recordings(_ items: [FeedItem], filter: String, limit: Int = 8) -> [Recording] {
        let iso = ISO8601DateFormatter()
        var out: [Recording] = []
        for item in items {
            guard filter.isEmpty || RX.contains(filter, in: item.title) else { continue }
            let id = item.fields["videoId"]
                ?? RX.first("[?&]v=([A-Za-z0-9_-]{6,})", in: item.link).flatMap { RX.group($0, 1, in: item.link) }
            guard let id else { continue }
            let url = item.link.isEmpty ? "https://www.youtube.com/watch?v=\(id)" : item.link
            out.append(Recording(videoID: id, title: item.title, url: url, published: iso.date(from: item.published)))
            if out.count >= limit { break }
        }
        return out
    }

    static func youTubeID(_ url: String) -> String? {
        if let m = RX.first("youtu\\.be/([A-Za-z0-9_-]{6,})", in: url) { return RX.group(m, 1, in: url) }
        if let m = RX.first("[?&]v=([A-Za-z0-9_-]{6,})", in: url) { return RX.group(m, 1, in: url) }
        if let m = RX.first("/(?:live|embed|shorts)/([A-Za-z0-9_-]{6,})", in: url) { return RX.group(m, 1, in: url) }
        return nil
    }
}
