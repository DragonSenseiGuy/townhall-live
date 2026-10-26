import Foundation

// The pure half of batch title translation: cache-key normalization, a
// tolerant reader for the model's reply, and a batch runner that keeps what
// came back, retries what didn't in smaller batches, and backs off when the
// endpoint is unreachable. No networking or UI here, so it can be tested
// with a mock model.

nonisolated enum TranslationText {
    /// Whitespace-insensitive form used for cache keys, so the same title
    /// scraped with different line wrapping (warrant vs. results) shares one entry.
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

nonisolated enum TranslationReply {
    /// Reads the model's answer to a batch of `count` strings sent as
    /// `{"1": "…", "2": "…"}`. Accepts code fences, an object keyed by id
    /// (1- or 0-based), an object wrapping an array, an array of strings (by
    /// position, only when the count matches), an array of
    /// `{"id": …, "text": …}` objects, or numbered lines. Returns index → text
    /// for whatever it could match; missing indexes are simply absent.
    static func parse(_ raw: String, count: Int) -> [Int: String] {
        guard count > 0 else { return [:] }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = RX.replace("(?m)^\\s*```[A-Za-z]*\\s*$", in: text, with: "")
        text = text.replacingOccurrences(of: "```", with: "")

        var out: [Int: String] = [:]
        if let json = jsonValue(in: text) { out = read(json, count: count) }
        if out.isEmpty { out = numberedLines(text, count: count) }
        return out.filter { (0..<count).contains($0.key) && !$0.value.isEmpty }
    }

    private static func jsonValue(in text: String) -> Any? {
        var candidates: [String] = []
        let opens: [(Character, Character)] = [("{", "}"), ("[", "]")]
        // Whichever bracket comes first is the outer value.
        let ordered = opens.sorted { a, b in
            (text.firstIndex(of: a.0) ?? text.endIndex) < (text.firstIndex(of: b.0) ?? text.endIndex)
        }
        for (open, close) in ordered {
            if let start = text.firstIndex(of: open), let end = text.lastIndex(of: close), start < end {
                candidates.append(String(text[start...end]))
            }
        }
        for candidate in candidates {
            for variant in [candidate, RX.replace(",\\s*([}\\]])", in: candidate, with: "$1")] {
                if let data = variant.data(using: .utf8),
                   let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    return value
                }
            }
        }
        return nil
    }

    private static func read(_ value: Any, count: Int) -> [Int: String] {
        if let dict = value as? [String: Any] {
            // {"translations": [...]} or {"result": {...}}
            if dict.count == 1, let inner = dict.values.first, inner is [Any] || inner is [String: Any],
               Int(dict.keys.first!.trimmingCharacters(in: .whitespaces)) == nil {
                return read(inner, count: count)
            }
            var numbered: [(Int, String)] = []
            for (key, v) in dict {
                guard let n = Int(key.trimmingCharacters(in: CharacterSet(charactersIn: " #id_-"))),
                      let s = string(v) else { continue }
                numbered.append((n, s))
            }
            let zeroBased = numbered.contains { $0.0 == 0 }
            var out: [Int: String] = [:]
            for (n, s) in numbered { out[zeroBased ? n : n - 1] = s }
            return out
        }
        if let array = value as? [Any] {
            if array.allSatisfy({ $0 is String }) {
                // Positional only when nothing was dropped or merged.
                guard array.count == count else { return [:] }
                var out: [Int: String] = [:]
                for (i, v) in array.enumerated() { out[i] = string(v) }
                return out
            }
            var numbered: [(Int, String)] = []
            for item in array {
                guard let obj = item as? [String: Any] else { continue }
                let id = ["id", "i", "index", "key", "n", "number"].lazy.compactMap { k -> Int? in
                    if let n = obj[k] as? Int { return n }
                    if let s = obj[k] as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
                    return nil
                }.first
                let s = ["text", "translation", "translated", "t", "value", "output"].lazy.compactMap { obj[$0].flatMap(string) }.first
                if let id, let s { numbered.append((id, s)) }
            }
            if numbered.isEmpty { return [:] }
            let zeroBased = numbered.contains { $0.0 == 0 }
            var out: [Int: String] = [:]
            for (n, s) in numbered { out[zeroBased ? n : n - 1] = s }
            return out
        }
        return [:]
    }

    private static func string(_ value: Any) -> String? {
        guard let s = value as? String else { return nil }
        let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// `1. 翻译` / `"2": "翻译",` lines.
    private static func numberedLines(_ text: String, count: Int) -> [Int: String] {
        var out: [Int: String] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let m = RX.first("^\\s*\"?(\\d{1,3})\"?\\s*[:.)\\-]\\s*\"?(.+?)\"?,?\\s*$", in: line),
                  let n = RX.group(m, 1, in: line).flatMap(Int.init),
                  let s = RX.group(m, 2, in: line)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { continue }
            out[n - 1] = s
        }
        return out.count >= 1 ? out : [:]
    }
}

/// Runs a list of strings through a batch translator. Kept translations are
/// delivered as they arrive; strings missing from a reply (or in a reply
/// that couldn't be read) are retried in smaller batches, down to one at a
/// time, and given up on for the session after `maxAttempts`. Network or
/// endpoint errors back off and retry the same batch; after
/// `maxTransientFailures` in a row the rest is returned for a later pass.
struct TranslationRunner {
    var batchSize = 12
    var batchCharacters = 1500
    var maxAttempts = 3
    var maxTransientFailures = 4
    /// Seconds before the n-th consecutive retry (1-based).
    var backoff: (Int) -> Double = { n in min(30, 2 * pow(2, Double(n - 1))) }

    /// index in the batch → translation.
    let translate: ([String]) async throws -> [Int: String]
    /// Errors that mean "the reply was unusable" rather than "try again later".
    let isUnusableReply: (Error) -> Bool
    let sleep: (Double) async -> Void
    /// False when the pass should stop (language changed).
    let shouldContinue: () -> Bool
    /// source text → translation, called after every batch that returned something.
    let deliver: ([String: String]) -> Void

    struct Outcome {
        /// Not attempted or interrupted by network failures: try again later.
        var deferred: [String] = []
        /// The model never returned a usable translation: skip for this session.
        var rejected: [String] = []
    }

    func batches(_ texts: [String]) -> [[String]] {
        var out: [[String]] = []
        var batch: [String] = []
        var characters = 0
        for text in texts {
            if !batch.isEmpty, batch.count >= batchSize || characters + text.count > batchCharacters {
                out.append(batch)
                batch = []
                characters = 0
            }
            batch.append(text)
            characters += text.count
        }
        if !batch.isEmpty { out.append(batch) }
        return out
    }

    func run(_ texts: [String]) async -> Outcome {
        var work = batches(texts)
        var attempts: [String: Int] = [:]
        var outcome = Outcome()
        var transient = 0

        func retry(_ missing: [String]) {
            var again: [String] = []
            for text in missing {
                attempts[text, default: 0] += 1
                if attempts[text]! >= maxAttempts { outcome.rejected.append(text) } else { again.append(text) }
            }
            guard !again.isEmpty else { return }
            if again.count == 1 {
                work.insert(again, at: 0)
            } else {
                let half = (again.count + 1) / 2
                work.insert(Array(again[half...]), at: 0)
                work.insert(Array(again[..<half]), at: 0)
            }
        }

        while !work.isEmpty {
            guard shouldContinue() else {
                outcome.deferred += work.flatMap { $0 }
                return outcome
            }
            let batch = work.removeFirst()
            do {
                let out = try await translate(batch)
                transient = 0
                var got: [String: String] = [:]
                var missing: [String] = []
                for (i, source) in batch.enumerated() {
                    if let t = out[i]?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                        got[source] = t
                    } else {
                        missing.append(source)
                    }
                }
                if !got.isEmpty { deliver(got) }
                if !missing.isEmpty { retry(missing) }
            } catch let error where isUnusableReply(error) {
                transient = 0
                retry(batch)
            } catch {
                transient += 1
                if transient >= maxTransientFailures {
                    outcome.deferred += batch + work.flatMap { $0 }
                    return outcome
                }
                work.insert(batch, at: 0)
                await sleep(backoff(transient))
            }
        }
        return outcome
    }
}
