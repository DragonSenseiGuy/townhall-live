import Foundation

// Live, scraped content in the interface language.
//
// Recurring shapes (meeting names, outcome labels, tallies, the app's own
// notes, dates) are localized deterministically from the String Catalog by
// `ContentPatterns` — no AI, works offline. Free-form text (recording titles,
// article titles, curated notes) is batch-translated through AIService when
// a non-English language is chosen and an AI key is set: one request per
// batch of short strings, cached on disk per language + hash of the
// whitespace-normalized text, applied in the background so the UI shows
// English until a translation arrives. A reply that covers only part of a
// batch keeps what it covers and retries the rest in smaller batches
// (`TranslationRunner`); network failures back off and retry in-session.
// Official legal text is never sent: it stays in its original English.

@Observable
final class ContentTranslator {
    static let shared = ContentTranslator()

    /// "lang|hash of the whitespace-normalized text" → translated text.
    /// Observable: views reading `LT()` re-render as batches arrive.
    private(set) var translations: [String: String] = [:]
    private(set) var isTranslating = false
    /// The town's own name, kept as written when it leads a meeting name.
    var properNouns: [String] = []

    /// Texts waiting for a pass, in priority order (most visible first).
    @ObservationIgnored private var pending: [String] = []
    /// Keys the model never answered usably this session (after retries).
    @ObservationIgnored private var rejected: Set<String> = []
    /// Delayed retries scheduled after network failures this session.
    @ObservationIgnored private var retryRound = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    static func key(_ text: String, _ language: AppLanguage) -> String {
        "\(language.rawValue)|\(TextHash.of(TranslationText.normalized(text)))"
    }

    /// The pre-normalization key, so translations cached by older builds still apply.
    private static func legacyKey(_ text: String, _ language: AppLanguage) -> String {
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
        return translations[Self.key(text, language)] ?? translations[Self.legacyKey(text, language)]
    }

    /// Queues whatever of `texts` is not cached yet for translation into the
    /// interface language (AI key required) and starts a background pass in
    /// an unstructured task, so leaving a screen never cancels it. Calls made
    /// while a pass runs add to the queue (new texts first) instead of
    /// replacing it, so one screen's request never drops another's.
    func translate(_ texts: [String]) {
        var seen = Set<String>()
        pending = (texts + pending).filter { seen.insert(TranslationText.normalized($0)).inserted }
        guard !isTranslating else { return }
        isTranslating = true
        Task {
            while !pending.isEmpty {
                let batch = pending
                pending = []
                await runPass(batch)
            }
            isTranslating = false
        }
    }

    private func needsWork(_ text: String, _ language: AppLanguage) -> Bool {
        guard text.rangeOfCharacter(from: .letters) != nil else { return false }
        let key = Self.key(text, language)
        return cached(text, language: language) == nil && !rejected.contains(key)
    }

    private func runPass(_ texts: [String]) async {
        let language = AppSettings.shared.language
        guard language != .english, AppSettings.shared.hasAPIKey else { return }
        let todo = texts.map(TranslationText.normalized).filter { needsWork($0, language) }
        guard !todo.isEmpty else { return }

        let runner = TranslationRunner(
            translate: { batch in try await AIService().translate(texts: batch, into: language) },
            isUnusableReply: { error in
                if case AIService.AIError.badResponse = error { return true }
                return error is DecodingError
            },
            sleep: { seconds in try? await Task.sleep(for: .seconds(seconds)) },
            shouldContinue: { AppSettings.shared.language == language && AppSettings.shared.hasAPIKey },
            deliver: { [weak self] got in
                guard let self else { return }
                var updated = self.translations
                for (source, translated) in got { updated[Self.key(source, language)] = translated }
                self.translations = updated
                LiveCache.save(updated, to: LiveCache.textTranslationsFile)
            }
        )
        let outcome = await runner.run(todo)
        outcome.rejected.forEach { rejected.insert(Self.key($0, language)) }
        if !outcome.rejected.isEmpty {
            LiveLog.log("AI content translation into \(language.englishName): \(outcome.rejected.count) strings unreadable after retries")
        }
        if AppSettings.shared.language != language {
            // Language switched mid-pass: start over in the new one.
            pending = texts + pending
            return
        }
        if !outcome.deferred.isEmpty { scheduleRetry(outcome.deferred) }
    }

    /// Offline or rate-limited: try the rest again later in this session
    /// (1, 2, 4, then every 8 minutes) instead of waiting for a relaunch.
    private func scheduleRetry(_ texts: [String]) {
        LiveLog.log("AI content translation paused; \(texts.count) strings will be retried")
        retryTask?.cancel()
        let minutes = Double(min(8, 1 << min(retryRound, 3)))
        retryRound += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self else { return }
            self.translate(texts)
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
