import Foundation

/// Single source of truth for the language the app UI is actually running in.
///
/// Supported localizations are exactly en, zh-Hans, zh-Hant and es. Any other device language
/// (fr, ja, de, …) resolves to the development language, English, via `Bundle.preferredLocalizations`.
/// Formatting (dates, numbers, PDF text) and the Gemini narrative language follow this value so a
/// French device never ends up with English UI but French month names in the PDF.
enum AppLocale {
    static let supportedLanguages = ["en", "zh-Hans", "zh-Hant", "es"]

    /// "en", "zh-Hans", "zh-Hant" or "es".
    static var languageCode: String {
        resolveLanguage(from: Bundle.main.preferredLocalizations)
    }

    static func resolveLanguage(from preferred: [String]) -> String {
        for identifier in preferred {
            if let match = supportedLanguages.first(where: { $0.caseInsensitiveCompare(identifier) == .orderedSame }) {
                return match
            }
        }
        return "en"
    }

    /// App language combined with the user's region, e.g. "es_US", "zh-Hant_TW", "en_GB".
    static var locale: Locale {
        locale(forLanguage: languageCode, region: Locale.current.region)
    }

    static func locale(forLanguage language: String, region: Locale.Region?) -> Locale {
        var components = Locale.Components(identifier: language)
        if let region {
            components.region = region
        }
        return Locale(components: components)
    }

    /// Human-readable target language handed to Gemini so narratives match the UI language.
    static var aiOutputLanguage: String {
        aiOutputLanguage(for: languageCode)
    }

    static func aiOutputLanguage(for language: String) -> String {
        switch language {
        case "zh-Hans": return "Simplified Chinese (zh-Hans)"
        case "zh-Hant": return "Traditional Chinese (zh-Hant, Taiwan usage and terminology)"
        case "es": return "Spanish (es, neutral Latin American)"
        default: return "English (en-US)"
        }
    }
}
