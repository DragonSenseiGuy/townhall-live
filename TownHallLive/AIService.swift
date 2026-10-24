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

    private static func firstJSONObject(in text: String) -> Data? {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}"),
            start < end
        else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }
}
