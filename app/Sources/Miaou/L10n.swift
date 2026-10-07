import Foundation

/// Key-based localization through the package resource bundle
/// (`Bundle.module`).
///
/// Resolution order for every key:
/// 1. the `language` user default, when set to "fr" or "en" (the in-app
///    language picker): that catalog is loaded directly from the matching
///    `.lproj` directory;
/// 2. otherwise the system language, via NSLocalizedString.
///
/// A missing catalog entry falls back to the key itself: visible in the
/// UI, never a crash. Date formatting goes through `L10n.locale` so a
/// forced language also localizes month and day names.
enum L10n {
    private static let overrideKey = "language"
    private static let lock = NSLock()
    private static var cache: [String: [String: String]] = [:]

    /// The forced language from the user default, when valid.
    private static var forcedLanguage: String? {
        switch UserDefaults.standard.string(forKey: overrideKey) {
        case "fr", "en":
            return UserDefaults.standard.string(forKey: overrideKey)
        default:
            return nil
        }
    }

    /// Locale matching the resolved language: forced language if set,
    /// else the system locale. Use for date formatting.
    static var locale: Locale {
        switch forcedLanguage {
        case "fr": return Locale(identifier: "fr_FR")
        case "en": return Locale(identifier: "en_US")
        default: return .current
        }
    }

    /// Look up `key` in the resolved Localizable.strings.
    static func t(_ key: String) -> String {
        if let lang = forcedLanguage, let value = catalog(lang)[key] {
            return value
        }
        return NSLocalizedString(key, bundle: .module, comment: "")
    }

    /// Localized format string, then `String(format:)`. Numbers stay in
    /// the C style (period decimal): formatTokens and the bar label do the
    /// same, so costs and token counts stay consistent across the UI.
    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    /// The key/value pairs of one language catalog, loaded once.
    private static func catalog(_ lang: String) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[lang] { return cached }
        guard let path = Bundle.module.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: lang
        ), let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            cache[lang] = [:]
            return [:]
        }
        cache[lang] = dict
        return dict
    }
}
