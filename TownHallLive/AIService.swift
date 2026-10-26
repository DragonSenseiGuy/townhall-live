import Foundation
import OSLog

// Chat-completions client for any OpenAI-compatible endpoint
// (Hack Club AI by default; base URL is user-configurable, OpenRouter shape).
struct AIService {
    private let logger = Logger(subsystem: "com.townhalllive", category: "ai")
    private var settings: AppSettings { .shared }

    struct Message: Codable, Sendable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Codable, Sendable {
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatResponse: Codable {
        struct Choice: Codable {
            struct Content: Codable { let content: String? }
            let message: Content
        }
        let choices: [Choice]
    }

    enum AIError: LocalizedError {
        case noKey
        case badURL
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noKey: "No API key set. Add one in Settings (Hack Club AI is free for students)."
            case .badURL: "The endpoint URL in Settings is not valid."
            case .http(let code, let body): "Endpoint returned HTTP \(code): \(body.prefix(160))"
            case .badResponse: "Could not read the model's response."
            }
        }
    }

    /// Raw chat completion against the configured endpoint.
    func complete(messages: [Message]) async throws -> String {
        let key = settings.apiKey
        guard !key.isEmpty else { throw AIError.noKey }

        let trimmedBase = settings.baseURL.hasSuffix("/") ? String(settings.baseURL.dropLast()) : settings.baseURL
        guard let url = URL(string: trimmedBase + "/chat/completions") else { throw AIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(model: settings.model, messages: messages, temperature: 0.2)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw AIError.badResponse
        }
        logger.debug("AI completion ok, \(content.count, privacy: .public) chars")
        return content
    }

    /// Re-generates a plain-English translation of a warrant article at runtime.
    func translate(article: WarrantArticle) async throws -> PlainEnglish {
        let system = """
        You translate Massachusetts town meeting warrant articles into plain English \
        for everyday residents. Reply with ONLY minified JSON matching exactly this shape: \
        {"summary": string (2-3 sentences), "keyTakeaways": [3-5 short strings], \
        "votingYesMeans": string (1 sentence), "votingNoMeans": string (1 sentence)}. \
        No markdown, no commentary. Be precise about dollar amounts names and outcomes.
        """
        let user = """
        Warrant article \(article.number): \(article.title)
        Category: \(article.category)
        Original text: \(article.originalText)
        \(article.financialImpact.map { "Financial facts: \($0.amount) — \($0.explanation)" } ?? "")
        """
        let raw = try await complete(messages: [
            Message(role: "system", content: system),
            Message(role: "user", content: user),
        ])
        guard let body = Self.firstJSONObject(in: raw),
              let parsed = try? JSONDecoder().decode(PlainEnglish.self, from: body) else {
            throw AIError.badResponse
        }
        return parsed
    }

    /// Translates an existing plain-English summary into another language,
    /// keeping the same JSON shape (dollar figures and names unchanged).
    func translate(plain: PlainEnglish, into language: AppLanguage) async throws -> PlainEnglish {
        let system = """
        You translate short civic explanations from English into \(language.englishName) for everyday \
        residents. Keep dollar amounts, numbers, article numbers, place names and proper nouns exact. \
        Reply with ONLY minified JSON with exactly the same keys as the input: \
        {"summary": string, "keyTakeaways": [strings], "votingYesMeans": string, "votingNoMeans": string}. \
        Translate every value into \(language.englishName). No markdown, no commentary.
        """
        let input = try JSONEncoder().encode(plain)
        let raw = try await complete(messages: [
            Message(role: "system", content: system),
            Message(role: "user", content: String(decoding: input, as: UTF8.self)),
        ])
        guard let body = Self.firstJSONObject(in: raw),
              let parsed = try? JSONDecoder().decode(PlainEnglish.self, from: body) else {
            throw AIError.badResponse
        }
        return parsed
    }

    /// Translates a batch of short scraped strings (meeting and recording
    /// titles, article titles) into another language in one request. Sent as
    /// a JSON object keyed by id ("1", "2", …) so the reply can be matched
    /// item by item; returns index in `texts` → translation for every item
    /// the reply contained (possibly fewer than were sent). Throws
    /// `badResponse` only when nothing in the reply could be matched.
    func translate(texts: [String], into language: AppLanguage) async throws -> [Int: String] {
        guard !texts.isEmpty else { return [:] }
        let system = """
        You translate short titles and notes from a Massachusetts town government (meeting names, \
        video titles, warrant article titles, vote notes) from English into \(language.englishName). \
        Keep numbers, dates, dollar amounts, article numbers, people's names, street and place names, \
        and the names of the town and its schools exact. The input is a JSON object mapping ids to \
        English strings. Reply with ONLY a JSON object with exactly the same ids, each mapped to its \
        \(language.englishName) translation. Translate every item; never merge, split or skip items. \
        No markdown, no commentary.
        """
        // Built by hand to keep the ids in numeric order.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var fields: [String] = []
        for (i, text) in texts.enumerated() {
            fields.append("\"\(i + 1)\":" + String(decoding: try encoder.encode(text), as: UTF8.self))
        }
        let raw = try await complete(messages: [
            Message(role: "system", content: system),
            Message(role: "user", content: "{" + fields.joined(separator: ",") + "}"),
        ])
        let parsed = TranslationReply.parse(raw, count: texts.count)
        guard !parsed.isEmpty else {
            logger.debug("unreadable batch translation reply: \(String(raw.prefix(200)), privacy: .public)")
            throw AIError.badResponse
        }
        return parsed
    }

    private static func firstJSONObject(in text: String) -> Data? {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}"),
            start < end
        else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }
}
