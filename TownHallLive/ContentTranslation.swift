import Foundation

// Live, scraped content in the interface language.
//
// Recurring shapes (meeting names, outcome labels, tallies, the app's own
// notes, dates) are localized deterministically from the String Catalog by
// `ContentPatterns` — no AI, works offline. Free-form text (recording titles,
// article titles, curated notes) is batch-translated through AIService when
// a non-English language is chosen and an AI key is set: one request per
// batch of short strings, cached on disk per language + text hash, applied in
// the background so the UI shows English until a translation arrives.
// Official legal text is never sent: it stays in its original English.

@Observable
final class ContentTranslator {
    static let shared = ContentTranslator()

    static let batchSize = 30
    static let batchCharacters = 3500

    /// "lang|hash" → translated text.
    private(set) var translations: [String: String] = [:]
    private(set) var isTranslating = false
    /// The town's own name, kept as written when it leads a meeting name.
    var properNouns: [String] = []

    @ObservationIgnored private var rerun = false
    @ObservationIgnored private var queued: [String] = []
    /// Batches the model answered unusably; not retried until relaunch.
    @ObservationIgnored private var rejected: Set<String> = []

    static func key(_ text: String, _ language: AppLanguage) -> String {
        "\(language.rawValue)|\(TextHash.of(text))"
    }

    func patterns(_ language: AppLanguage) -> ContentPatterns {
        ContentPatterns(locale: language.locale,
                        lookup: { Localizer.string($0, language: language) },
                        properNouns: properNouns)
    }

    init() {
        translations = LiveCache.load([String: String].self, from: LiveCache.textTranslationsFile) ?? [:]
    }

    func cached(_ text: String, language: AppLanguage) -> String? {
        guard language != .english else { return text }
        return translations[Self.key(text, language)]
    }

    /// Translates whatever of `texts` is not cached yet into the interface
    /// language (AI key required), in an unstructured task so leaving a
    /// screen never cancels it. A call made while a pass is running replaces
    /// the queue and runs right after it.
    func translate(_ texts: [String]) {
        queued = texts
        guard !isTranslating else { rerun = true; return }
        isTranslating = true
        Task {
            repeat {
                rerun = false
                await runPass(queued)
            } while rerun
            isTranslating = false
        }
    }

    private func runPass(_ texts: [String]) async {
        let language = AppSettings.shared.language
        guard language != .english, AppSettings.shared.hasAPIKey else { return }
        var seen = Set<String>()
        let todo = texts.filter { text in
            guard text.rangeOfCharacter(from: .letters) != nil else { return false }
            let key = Self.key(text, language)
            return translations[key] == nil && !rejected.contains(key) && seen.insert(key).inserted
        }
        guard !todo.isEmpty else { return }

        var failures = 0
        var index = 0
        while index < todo.count {
            // Language switched mid-pass: start over in the new one.
            if AppSettings.shared.language != language { rerun = true; return }
            var batch: [String] = []
            var characters = 0
            while index < todo.count, batch.count < Self.batchSize,
                  batch.isEmpty || characters + todo[index].count <= Self.batchCharacters {
                batch.append(todo[index])
                characters += todo[index].count
                index += 1
            }
            do {
                let out = try await AIService().translate(texts: batch, into: language)
                var updated = translations
                for (source, translated) in zip(batch, out) {
                    let clean = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { updated[Self.key(source, language)] = clean }
                }
                translations = updated
                LiveCache.save(translations, to: LiveCache.textTranslationsFile)
                failures = 0
            } catch {
                LiveLog.log("AI content translation into \(language.englishName) failed: \(error.localizedDescription)")
                if case AIService.AIError.badResponse = error {
                    batch.forEach { rejected.insert(Self.key($0, language)) }
                }
                failures += 1
                if failures >= 3 { return } // offline or no quota — try again on the next refresh
            }
        }
    }
}

// MARK: - Display helpers (read inside a view's body to follow language changes)

private var contentLanguage: AppLanguage { AppSettings.shared.language }

/// Free-form scraped text in the interface language: a known generated
/// sentence from the catalog, else the cached AI translation, else English.
func LT(_ text: String) -> String {
    let language = contentLanguage
    guard language != .english, !text.isEmpty else { return text }
    let translator = ContentTranslator.shared
    if let generated = translator.patterns(language).generatedText(text) { return generated }
    return translator.cached(text, language: language) ?? text
}

/// A meeting name ("Special Town Meeting · November 25, 2024", a recording
/// title): composed from catalog parts when it is a known shape, else AI/English.
func meetingNameText(_ name: String) -> String {
    let language = contentLanguage
    guard language != .english, !name.isEmpty else { return name }
    let translator = ContentTranslator.shared
    return translator.patterns(language).meetingName(name)
        ?? translator.cached(name, language: language)
        ?? name
}

/// A scraped date line with dates and times re-formatted for the interface locale.
func dateLineText(_ line: String) -> String {
    let language = contentLanguage
    guard language != .english else { return line }
    return ContentTranslator.shared.patterns(language).dateLine(line)
}

/// "Approved 357–38" / "Unanimous" with the outcome word localized.
func tallyText(_ tally: String) -> String {
    let language = contentLanguage
    guard language != .english else { return tally }
    return ContentTranslator.shared.patterns(language).tally(tally)
}

/// Free-form texts that need the AI in the current language (known shapes excluded).
func needsAITranslation(_ text: String, asMeetingName: Bool = false) -> Bool {
    let language = contentLanguage
    guard language != .english, text.rangeOfCharacter(from: .letters) != nil else { return false }
    let patterns = ContentTranslator.shared.patterns(language)
    if asMeetingName { return patterns.meetingName(text) == nil }
    return patterns.generatedText(text) == nil
}
