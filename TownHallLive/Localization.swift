import SwiftUI

// In-app language switching. The interface language is the user's choice in
// Settings (UserDefaults), not only the iOS setting: every UI string goes
// through `L(_:)`, which reads the chosen language's compiled String Catalog
// table (`<lang>.lproj/Localizable.strings`) straight from the bundle, so a
// change applies on the next render. The root view also sets `\.locale` (for
// system formatting) and `\.layoutDirection` (right-to-left for Arabic).

nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case spanish = "es"
    case hindi = "hi"
    case arabic = "ar"

    static let defaultsKey = "app.language"

    var id: String { rawValue }

    /// Name shown in the picker, always in the language itself.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .chineseSimplified: "简体中文"
        case .spanish: "Español"
        case .hindi: "हिन्दी"
        case .arabic: "العربية"
        }
    }

    /// English name, used in AI prompts.
    var englishName: String {
        switch self {
        case .english: "English"
        case .chineseSimplified: "Simplified Chinese"
        case .spanish: "Spanish"
        case .hindi: "Hindi"
        case .arabic: "Arabic"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
    var isRightToLeft: Bool { self == .arabic }
    var layoutDirection: LayoutDirection { isRightToLeft ? .rightToLeft : .leftToRight }

    /// Saved choice, or the first supported language in the device's
    /// preferred languages, or English.
    static func stored(in defaults: UserDefaults) -> AppLanguage {
        if let raw = defaults.string(forKey: defaultsKey), let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        for preferred in Locale.preferredLanguages {
            let lower = preferred.lowercased()
            if lower.hasPrefix("zh-hans") || lower == "zh-cn" || lower.hasPrefix("zh-cn") { return .chineseSimplified }
            if lower.hasPrefix("es") { return .spanish }
            if lower.hasPrefix("hi") { return .hindi }
            if lower.hasPrefix("ar") { return .arabic }
            if lower.hasPrefix("en") { return .english }
        }
        return .english
    }
}

enum Localizer {
    private static var bundles: [AppLanguage: Bundle] = [:]

    static func bundle(for language: AppLanguage) -> Bundle {
        if let cached = bundles[language] { return cached }
        let found = Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:))
            ?? Bundle.main
        bundles[language] = found
        return found
    }

    static func string(_ key: String, language: AppLanguage) -> String {
        bundle(for: language).localizedString(forKey: key, value: key, table: "Localizable")
    }
}

/// Localized UI string in the language chosen in Settings. Reading it inside a
/// view's body subscribes that view to language changes.
func L(_ key: String) -> String {
    Localizer.string(key, language: AppSettings.shared.language)
}

/// Localized format string; arguments are substituted for `%@` in order.
func L(_ key: String, _ args: String...) -> String {
    let format = L(key)
    var out = ""
    var remaining = args[...]
    var rest = Substring(format)
    while let range = rest.range(of: "%@") {
        out += rest[..<range.lowerBound]
        out += remaining.popFirst() ?? ""
        rest = rest[range.upperBound...]
    }
    out += rest
    return out
}

/// Display label for an official outcome value.
func outcomeLabel(_ result: String) -> String {
    switch result {
    case "passed": L("Passed")
    case "failed": L("Failed")
    case "no action": L("No action")
    case "postponed": L("Postponed")
    default: L(result.capitalized)
    }
}
