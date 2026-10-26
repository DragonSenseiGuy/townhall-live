import Foundation

// Deterministic, no-AI localization of the recurring shapes in scraped town
// content: meeting names ("Special Town Meeting - November 25, 2024",
// "<Town> Select Board Meeting - October 26th, 2026"), outcome labels and
// tallies ("Approved 357–38"), the app's own generated notes, and dates.
//
// Everything here is pure: a `ContentPatterns` value carries the target
// locale and a String Catalog lookup, so the rules can be exercised without
// the app bundle. A function returns nil when the text is not one of the
// known shapes; callers then fall back to the AI cache or the English text.

/// Parsed pieces of a scraped date string.
nonisolated enum ScrapedDate {
    static let monthNames: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sept": 9, "sep": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12,
    ]

    static let month = "(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)\\.?"
    static let weekday = "(?:(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Tues|Wed|Thu|Thur|Thurs|Fri|Sat|Sun)\\.?,?\\s+)"
    static let ordinal = "(?:st|nd|rd|th)?"

    /// "Monday, May 4, 2026", "October 26th, 2026", "Oct 26 2026".
    static let fullPattern = "(\(weekday))?\(month)\\s+(\\d{1,2})\(ordinal),?\\s+(\\d{4})"
    /// "May 4th and 5th 2026", "May 4 & 5, 2026", "May 4-5, 2026".
    static let pairPattern = "\(month)\\s+(\\d{1,2})\(ordinal)\\s*(and|&|-|\\u2013|\\u2014)\\s*(\\d{1,2})\(ordinal),?\\s+(\\d{4})"
    /// "10/26/2026", "10/26/26", "10-26-2026".
    static let numericPattern = "(?<![\\d/])(\\d{1,2})[/.\\-](\\d{1,2})[/.\\-](\\d{4}|\\d{2})(?![\\d/])"
    /// "November 2024", "November".
    static let monthOnlyPattern = "\\b\(month)(?:\\s+(\\d{4}))?"
    /// "7:00 PM", "7 pm", "7:30 p.m.".
    static let timePattern = "(\\d{1,2})(?::(\\d{2}))?\\s*([AaPp])\\.?\\s?[Mm]\\.?"

    static func make(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), (1900...2200).contains(year) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let comps = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: comps),
              calendar.component(.day, from: date) == day else { return nil } // rejects Feb 30
        return date
    }

    static func monthNumber(_ name: String) -> Int? {
        monthNames[name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))]
    }

    /// A whole string that is exactly one calendar date (optionally with a weekday).
    static func parseFull(_ text: String) -> (date: Date, hasWeekday: Bool)? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard let m = PX.whole(fullPattern, s),
              let mon = PX.group(m, 2, s).flatMap(monthNumber),
              let day = PX.group(m, 3, s).flatMap(Int.init),
              let year = PX.group(m, 4, s).flatMap(Int.init),
              let date = make(year: year, month: mon, day: day) else {
            return parseNumeric(s).map { ($0, false) }
        }
        return (date, PX.group(m, 1, s) != nil)
    }

    static func parseNumeric(_ text: String) -> Date? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard let m = PX.whole(numericPattern, s),
              let mon = PX.group(m, 1, s).flatMap(Int.init),
              let day = PX.group(m, 2, s).flatMap(Int.init),
              var year = PX.group(m, 3, s).flatMap(Int.init) else { return nil }
        if year < 100 { year += 2000 }
        return make(year: year, month: mon, day: day)
    }

    /// "May 4th and 5th 2026" → both days.
    static func parsePair(_ text: String) -> (Date, Date, joiner: String)? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard let m = PX.whole(pairPattern, s),
              let mon = PX.group(m, 1, s).flatMap(monthNumber),
              let d1 = PX.group(m, 2, s).flatMap(Int.init),
              let joiner = PX.group(m, 3, s),
              let d2 = PX.group(m, 4, s).flatMap(Int.init),
              let year = PX.group(m, 5, s).flatMap(Int.init),
              let a = make(year: year, month: mon, day: d1),
              let b = make(year: year, month: mon, day: d2) else { return nil }
        return (a, b, joiner)
    }

    /// "7:00 PM" → (19, 0).
    static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard let m = PX.whole(timePattern, s),
              var hour = PX.group(m, 1, s).flatMap(Int.init), (1...12).contains(hour) else { return nil }
        let minute = PX.group(m, 2, s).flatMap(Int.init) ?? 0
        guard (0...59).contains(minute) else { return nil }
        let pm = PX.group(m, 3, s)?.lowercased() == "p"
        if pm, hour < 12 { hour += 12 }
        if !pm, hour == 12 { hour = 0 }
        return (hour, minute)
    }

    /// First calendar date anywhere in the text ("… Meeting - October 26th, 2026").
    static func firstDate(in text: String) -> Date? {
        if let m = PX.first(fullPattern, text), let r = Range(m.range, in: text),
           let parsed = parseFull(String(text[r])) { return parsed.date }
        if let m = PX.first(numericPattern, text), let r = Range(m.range, in: text) {
            return parseNumeric(String(text[r]))
        }
        return nil
    }
}

/// One recurring meeting body the catalog translates.
nonisolated struct MeetingBody: Sendable {
    let pattern: String
    let key: String
    /// Boards and committees read "<board> Meeting" through the "%@ Meeting" format.
    let isBoard: Bool
}

nonisolated enum MeetingBodies {
    // Longest / most specific first.
    static let all: [MeetingBody] = [
        MeetingBody(pattern: "Annual\\s+Town\\s+Election\\s*\\(\\s*ballot\\s+questions?\\s*\\)", key: "Annual Town Election (ballot question)", isBoard: false),
        MeetingBody(pattern: "Town\\s+Water\\s+District\\s+Annual\\s+Meeting", key: "Town Water District Annual Meeting", isBoard: false),
        MeetingBody(pattern: "Water\\s+District\\s+Annual\\s+Meeting", key: "Water District Annual Meeting", isBoard: false),
        MeetingBody(pattern: "Water\\s+District\\s+Special\\s+Meeting", key: "Water District Special Meeting", isBoard: false),
        MeetingBody(pattern: "Water\\s+District\\s+Meeting", key: "Water District Meeting", isBoard: false),
        MeetingBody(pattern: "Annual\\s+Town\\s+Meeting", key: "Annual Town Meeting", isBoard: false),
        MeetingBody(pattern: "Special\\s+Town\\s+Meeting", key: "Special Town Meeting", isBoard: false),
        MeetingBody(pattern: "Annual\\s+Town\\s+Election", key: "Annual Town Election", isBoard: false),
        MeetingBody(pattern: "Special\\s+Town\\s+Election", key: "Special Town Election", isBoard: false),
        MeetingBody(pattern: "Presidential\\s+Primary", key: "Presidential Primary", isBoard: false),
        MeetingBody(pattern: "State\\s+Primary", key: "State Primary", isBoard: false),
        MeetingBody(pattern: "State\\s+Election", key: "State Election", isBoard: false),
        MeetingBody(pattern: "Special\\s+Election", key: "Special Election", isBoard: false),
        MeetingBody(pattern: "Town\\s+Election", key: "Town Election", isBoard: false),
        MeetingBody(pattern: "Town\\s+Meeting", key: "Town Meeting", isBoard: false),
        MeetingBody(pattern: "Regional\\s+School\\s+Committee", key: "Regional School Committee", isBoard: true),
        MeetingBody(pattern: "School\\s+Committee", key: "School Committee", isBoard: true),
        MeetingBody(pattern: "Select\\s+Board|Board\\s+of\\s+Selectmen", key: "Select Board", isBoard: true),
        MeetingBody(pattern: "Planning\\s+Board", key: "Planning Board", isBoard: true),
        MeetingBody(pattern: "Finance\\s+Committee", key: "Finance Committee", isBoard: true),
        MeetingBody(pattern: "Zoning\\s+Board\\s+of\\s+Appeals", key: "Zoning Board of Appeals", isBoard: true),
        MeetingBody(pattern: "Conservation\\s+Commission", key: "Conservation Commission", isBoard: true),
        MeetingBody(pattern: "Board\\s+of\\s+Health", key: "Board of Health", isBoard: true),
        MeetingBody(pattern: "Historical\\s+Commission", key: "Historical Commission", isBoard: true),
        MeetingBody(pattern: "Housing\\s+Authority", key: "Housing Authority", isBoard: true),
        MeetingBody(pattern: "Board\\s+of\\s+Library\\s+Trustees|Library\\s+Trustees", key: "Board of Library Trustees", isBoard: true),
        MeetingBody(pattern: "Board\\s+of\\s+Assessors", key: "Board of Assessors", isBoard: true),
        MeetingBody(pattern: "Capital\\s+Planning\\s+Committee", key: "Capital Planning Committee", isBoard: true),
    ]
}

struct ContentPatterns {
    let locale: Locale
    /// String Catalog lookup in the target language (key → translation).
    let lookup: (String) -> String
    /// Proper nouns that may lead a meeting name and stay as written (the town's name).
    var properNouns: [String] = []

    // MARK: Catalog helpers

    private func format(_ key: String, _ args: String...) -> String {
        let fmt = lookup(key)
        var out = ""
        var remaining = args[...]
        var rest = Substring(fmt)
        while let range = rest.range(of: "%@") {
            out += rest[..<range.lowerBound]
            out += remaining.popFirst() ?? ""
            rest = rest[range.upperBound...]
        }
        return out + rest
    }

    private func localizedNumber(_ digits: String) -> String {
        Int(digits).map { $0.formatted(.number.grouping(.never).locale(locale)) } ?? digits
    }

    // MARK: Dates

    func formatDate(_ date: Date, weekday: Bool = false) -> String {
        var style = Date.FormatStyle(timeZone: .current).month(.wide).day().year()
        if weekday { style = style.weekday(.wide) }
        return date.formatted(style.locale(locale))
    }

    func formatMonthDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: .current).month(.wide).day().locale(locale))
    }

    func formatTime(hour: Int, minute: Int) -> String {
        let date = ScrapedDate.make(year: 2000, month: 1, day: 3, hour: hour, minute: minute) ?? Date()
        return date.formatted(Date.FormatStyle(timeZone: .current).hour().minute().locale(locale))
    }

    func formatMonth(_ month: Int, year: Int?) -> String {
        let date = ScrapedDate.make(year: year ?? 2000, month: month, day: 1) ?? Date()
        var style = Date.FormatStyle(timeZone: .current).month(.wide)
        if year != nil { style = style.year() }
        return date.formatted(style.locale(locale))
    }

    /// One date-ish segment, or nil when it is not a date or time.
    func dateSegment(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let (date, weekday) = ScrapedDate.parseFull(s) { return formatDate(date, weekday: weekday) }
        if let (a, b, joiner) = ScrapedDate.parsePair(s) {
            if joiner == "and" || joiner == "&" {
                return [formatMonthDay(a), formatDate(b)].formatted(.list(type: .and).locale(locale))
            }
            return (a..<b.addingTimeInterval(1)).formatted(
                Date.IntervalFormatStyle(date: .long, time: .omitted, locale: locale, timeZone: .current))
        }
        if let t = ScrapedDate.parseTime(s) { return formatTime(hour: t.hour, minute: t.minute) }
        if let m = PX.whole(ScrapedDate.monthOnlyPattern, s),
           let month = PX.group(m, 1, s).flatMap(ScrapedDate.monthNumber) {
            return formatMonth(month, year: PX.group(m, 2, s).flatMap(Int.init))
        }
        if s.caseInsensitiveCompare("Recording") == .orderedSame { return lookup("Recording") }
        if s.caseInsensitiveCompare("recently") == .orderedSame { return lookup("recently") }
        return nil
    }

    /// A " · "-separated date line ("Monday, May 4, 2026 · 7:00 PM · Auditorium"):
    /// dates and times are re-formatted in the locale, anything else (places,
    /// years) is kept as written.
    func dateLine(_ text: String) -> String {
        text.components(separatedBy: " · ")
            .map { dateSegment($0) ?? $0 }
            .joined(separator: " · ")
    }

    // MARK: Meeting names

    /// "Special Town Meeting - November 25, 2024", "2024 Special Town Meeting",
    /// "Annual Town Meeting · Day 2", "<Town> Select Board Meeting - October 26th, 2026".
    /// nil when anything other than a known body, the town's name, dates and
    /// session qualifiers is left over.
    func meetingName(_ text: String) -> String? {
        let s = PX.replace("\\s+", in: text.replacingOccurrences(of: "&amp;", with: "&"), with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        var found: (body: MeetingBody, range: Range<String.Index>)?
        for body in MeetingBodies.all {
            if let m = PX.first("(?<![\\p{L}])(?:\(body.pattern))(?![\\p{L}])", s, [.caseInsensitive]), let r = Range(m.range, in: s) {
                found = (body, r)
                break
            }
        }
        guard let (body, range) = found else { return nil }

        // Before the body: nothing, a year, or the town's own name.
        var prefixWords: [String] = []
        var years: [Int] = []
        for word in s[..<range.lowerBound].split(separator: " ").map(String.init) {
            let w = word.trimmingCharacters(in: CharacterSet(charactersIn: "-–—·|:,()"))
            if w.isEmpty { continue }
            if let y = Int(w), (1900...2200).contains(y) { years.append(y); continue }
            let lower = w.lowercased()
            guard properNouns.contains(where: { !$0.isEmpty && lower.contains($0.lowercased()) }) else { return nil }
            prefixWords.append(w)
        }

        // After the body: "Meeting", dates, years, session qualifiers, separators.
        var rest = String(s[range.upperBound...])
        var dates: [String] = []
        var dateYears: Set<Int> = []
        var qualifiers: [String] = []
        var hasMeetingWord = false

        func take(_ pattern: String, _ handle: (NSTextCheckingResult, String) -> Bool) {
            while let m = PX.first(pattern, rest, [.caseInsensitive]), let r = Range(m.range, in: rest) {
                guard handle(m, rest) else { break }
                rest.replaceSubrange(r, with: " ")
            }
        }

        take("\\bMeeting\\b") { _, _ in hasMeetingWord = true; return true }
        take(ScrapedDate.pairPattern) { m, str in
            guard let r = Range(m.range, in: str), let text = dateSegment(String(str[r])) else { return false }
            dates.append(text)
            if let y = PX.group(m, 5, str).flatMap(Int.init) { dateYears.insert(y) }
            return true
        }
        take(ScrapedDate.fullPattern) { m, str in
            guard let r = Range(m.range, in: str), let parsed = ScrapedDate.parseFull(String(str[r])) else { return false }
            dates.append(formatDate(parsed.date, weekday: parsed.hasWeekday))
            dateYears.insert(Calendar(identifier: .gregorian).component(.year, from: parsed.date))
            return true
        }
        take(ScrapedDate.numericPattern) { m, str in
            guard let r = Range(m.range, in: str), let date = ScrapedDate.parseNumeric(String(str[r])) else { return false }
            dates.append(formatDate(date))
            dateYears.insert(Calendar(identifier: .gregorian).component(.year, from: date))
            return true
        }
        take("\\b(Day|Night|Session|Part|Vol\\.?|Volume)\\s*#?\\s*(\\d{1,2})\\b") { m, str in
            guard let kind = PX.group(m, 1, str)?.lowercased(), let n = PX.group(m, 2, str) else { return false }
            let key = kind.hasPrefix("night") ? "Night %@" : kind.hasPrefix("session") ? "Session %@"
                : kind.hasPrefix("day") ? "Day %@" : "Part %@"
            qualifiers.append(format(key, localizedNumber(n)))
            return true
        }
        take("#\\s*(\\d{1,2})\\b") { m, str in
            guard let n = PX.group(m, 1, str) else { return false }
            qualifiers.append(format("Session %@", localizedNumber(n)))
            return true
        }
        take("\\b(Continued|Cont'd|Cont\\.)(?=\\W|$)") { _, _ in qualifiers.append(lookup("Continued")); return true }
        take("\\(?\\s*ballot\\s+questions?\\s*\\)?") { _, _ in qualifiers.append(lookup("Ballot question")); return true }
        take(ScrapedDate.monthOnlyPattern + "\\b") { m, str in
            guard let month = PX.group(m, 1, str).flatMap(ScrapedDate.monthNumber) else { return false }
            let year = PX.group(m, 2, str).flatMap(Int.init)
            dates.append(formatMonth(month, year: year))
            if let year { dateYears.insert(year) }
            return true
        }
        take("\\b((?:19|20)\\d{2})\\b") { m, str in
            if let y = PX.group(m, 1, str).flatMap(Int.init) { years.append(y) }
            return true
        }
        guard PX.whole("[\\s\\-\\u2013\\u2014\\u00B7|:,()/&.]*", rest) != nil else { return nil }

        var name: String
        if body.isBoard, hasMeetingWord {
            // Spanish contracts "de el" → "del".
            name = format("%@ Meeting", lookup(body.key))
                .replacingOccurrences(of: " de el ", with: " del ")
        } else {
            name = lookup(body.key)
        }
        // The town's own name stays as written, as its own segment, so it
        // never has to fit another language's word order.
        var parts = [name]
        if !prefixWords.isEmpty { parts.append(prefixWords.joined(separator: " ")) }
        parts += qualifiers + dates
        for y in years where !dateYears.contains(y) { parts.append(String(y)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Outcomes

    static let outcomeKeys: [String: String] = [
        "approved": "Approved", "adopted": "Adopted", "carried": "Carried", "carries": "Carried",
        "passed": "Passed", "passes": "Passed", "pass": "Passed",
        "failed": "Failed", "fails": "Failed", "defeated": "Defeated", "not approved": "Not Approved",
        "not adopted": "Not Adopted", "not carried": "Failed",
        "no action": "No action", "no action taken": "No Action Taken", "withdrawn": "Withdrawn",
        "passed over": "Passed Over", "indefinitely postponed": "Indefinitely Postponed",
        "postponed indefinitely": "Indefinitely Postponed", "postponed": "Postponed",
        "referred": "Referred", "referred back": "Referred", "tabled": "Tabled", "dismissed": "Dismissed",
        "unanimous": "Unanimous", "unanimously": "Unanimous",
    ]

    /// "No Action Taken" → catalog translation; nil for unknown labels.
    func outcomeWord(_ label: String) -> String? {
        let key = PX.replace("\\s+", in: label.lowercased(), with: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .;:"))
        return Self.outcomeKeys[key].map(lookup)
    }

    /// "Approved 357–38", "Unanimous", "243–26", "Approved Unanimous".
    func tally(_ text: String) -> String {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard let m = PX.whole("([A-Za-z][A-Za-z ]*?)?\\s*([\\d\\u2013\\-–— ,%]*)", s) else { return text }
        let words = PX.group(m, 1, s) ?? ""
        let numbers = (PX.group(m, 2, s) ?? "").trimmingCharacters(in: .whitespaces)
        var label = ""
        if !words.isEmpty {
            if let w = outcomeWord(words) {
                label = w
            } else if let lastSpace = words.lowercased().range(of: " unanimous", options: .backwards),
                      let first = outcomeWord(String(words[..<lastSpace.lowerBound])) {
                label = first + " " + lookup("Unanimous")
            } else {
                return text
            }
        }
        return [label, numbers].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Generated notes and fallback sentences (written by the app in English)

    func generatedText(_ text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespaces)
        if let m = PX.whole("Town Meeting results summary, town website \\(checked (.+)\\)\\.", s),
           let when = PX.group(m, 1, s) {
            return format("Town Meeting results summary, town website (checked %@).", dateSegment(when) ?? when)
        }
        if let m = PX.whole("Largest of (\\d+) dollar figures in the warrant text — see the original text for each line item\\.", s),
           let n = PX.group(m, 1, s) {
            return format("Largest of %@ dollar figures in the warrant text — see the original text for each line item.", n)
        }
        if let m = PX.whole("Dollar amount in the article: (.+)", s), let amount = PX.group(m, 1, s) {
            return format("Dollar amount in the article: %@", amount)
        }
        if let m = PX.whole("Article (\\d{1,3})", s), let n = PX.group(m, 1, s) {
            return format("Article %@", n)
        }
        let fixed = [
            "Dollar figure stated in the warrant text.",
            "Needs a two-thirds majority to pass",
            "Needs a simple majority to pass",
            "See the original warrant text below for the full details",
            "A yes vote approves the article as written in the warrant.",
            "A no vote rejects the article as written.",
        ]
        if fixed.contains(s) { return lookup(s) }
        return nil
    }
}

// MARK: - Regex helpers (self-contained so this file stands alone)

nonisolated enum PX {
    static func make(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    static func first(_ pattern: String, _ text: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> NSTextCheckingResult? {
        make(pattern, options)?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Match covering the whole string.
    static func whole(_ pattern: String, _ text: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> NSTextCheckingResult? {
        first("^(?:\(pattern))$", text, options)
    }

    static func group(_ m: NSTextCheckingResult, _ i: Int, _ text: String) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: text) else { return nil }
        return String(text[r])
    }

    static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let re = make(pattern) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
