import Foundation

/// Key-based localization through the native bundle, or `Bundle.module`
/// when built with Swift Package Manager.
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
    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

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
        locale(language: forcedLanguage ?? "system")
    }

    static func locale(language: String) -> Locale {
        switch language {
        case "fr": return Locale(identifier: "fr_FR")
        case "en": return Locale(identifier: "en_US")
        default: return .current
        }
    }

    /// Look up `key` in the resolved Localizable.strings.
    static func t(_ key: String) -> String {
        t(key, language: forcedLanguage ?? "system")
    }

    /// Widgets use the language published by the containing app.
    static func t(_ key: String, language: String) -> String {
        if ["fr", "en"].contains(language), let value = catalog(language)[key] {
            return value
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
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
        guard let path = bundle.path(
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
