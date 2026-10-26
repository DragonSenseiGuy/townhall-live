import Foundation
import Security

// Minimal Keychain wrapper: one generic-password item holds the AI API key.
enum KeychainStore {
    private static let service = "com.townhalllive.ai"
    private static let account = "api-key"

    static func save(_ secret: String) {
        guard let data = secret.data(using: .utf8) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// User-adjustable AI configuration: endpoint (OpenAI-compatible), model, key.
// Defaults are Hack Club AI so the demo runs with free student credits.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private static let baseURLKey = "ai.baseURL"
    private static let modelKey = "ai.model"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var baseURL: String {
        get { defaults.string(forKey: Self.baseURLKey) ?? "https://ai.hackclub.com/proxy/v1" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed, forKey: Self.baseURLKey)
        }
    }

    var model: String {
        get { defaults.string(forKey: Self.modelKey) ?? "openai/gpt-4o-mini" }
        set { defaults.set(newValue, forKey: Self.modelKey) }
    }

    var apiKey: String {
        get {
            // Dev/test hook (simctl can't tap or type): `defaults write
            // <bundleId> thl.testKey 1` lets CLI-driven tests exercise the AI
            // path without a real key. Harmless in production.
            if UserDefaults.standard.bool(forKey: "thl.testKey") { return "test-key" }
            return KeychainStore.load() ?? ""
        }
        set {
            if newValue.isEmpty { KeychainStore.delete() } else { KeychainStore.save(newValue) }
        }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    // Live-data source overrides (empty = use TownSources.plist).
    var townWebsiteOverride: String {
        get { defaults.string(forKey: TownSources.websiteOverrideKey) ?? "" }
        set { setOrClear(newValue, forKey: TownSources.websiteOverrideKey) }
    }

    var youtubeChannelOverride: String {
        get { defaults.string(forKey: TownSources.youtubeOverrideKey) ?? "" }
        set { setOrClear(newValue, forKey: TownSources.youtubeOverrideKey) }
    }

    private func setOrClear(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(trimmed, forKey: key) }
    }
}
