import XCTest
@testable import Miaou

/// Catalog parity: the en and fr Localizable.strings must exist, parse and
/// carry the same key set, so a new key cannot ship half-translated.
final class L10nTests: XCTestCase {
    private func catalog(_ localization: String) throws -> [String: String] {
        let path = try XCTUnwrap(
            Bundle.module.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: localization
            ),
            "missing Localizable.strings for \(localization)"
        )
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    func testBothLanguagesShippedAndInSync() throws {
        let en = try catalog("en")
        let fr = try catalog("fr")
        XCTAssertFalse(en.isEmpty)
        XCTAssertEqual(Set(en.keys), Set(fr.keys))
    }

    func testSpotChecks() throws {
        XCTAssertEqual(try catalog("en")["today.headline"], "Today")
        XCTAssertEqual(try catalog("fr")["today.headline"], "Aujourd'hui")
        XCTAssertEqual(try catalog("fr")["settings.headline"], "Réglages")
        XCTAssertEqual(try catalog("en")["quit.button"], "Quit")
        XCTAssertEqual(try catalog("fr")["quit.button"], "Quitter")
    }

    /// The `language` user default forces the catalog, bypassing the
    /// system language.
    func testForcedLanguageOverride() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "language") }

        defaults.set("fr", forKey: "language")
        XCTAssertEqual(L10n.t("today.headline"), "Aujourd'hui")
        XCTAssertEqual(L10n.locale.identifier, "fr_FR")

        defaults.set("en", forKey: "language")
        XCTAssertEqual(L10n.t("today.headline"), "Today")

        defaults.set("system", forKey: "language")
        XCTAssertEqual(L10n.locale, .current)
    }

    func testWidgetConfigurationLabelsHaveReadableDefaultsAndTranslations() throws {
        guard #available(macOS 14.0, *) else { return }
        let configuration = ChatonWidgetConfiguration()
        let labels: [(LocalizedStringResource, String, String)] = [
            (configuration.$mode.title, "Animation", "Animation"),
            (configuration.$pet.title, "Cat", "Chat"),
            (try XCTUnwrap(ChatonAnimationMode.caseDisplayRepresentations[.always]).title,
             "Always", "Toujours"),
            (try XCTUnwrap(ChatonAnimationMode.caseDisplayRepresentations[.session]).title,
             "When a session is active", "Quand une session est active"),
            (try XCTUnwrap(BarPet.caseDisplayRepresentations[.chaton]).title, "Chaton", "Chaton"),
            (try XCTUnwrap(BarPet.caseDisplayRepresentations[.chonk]).title, "Le Chonk", "Le Chonk"),
        ]
        let en = try catalog("en")
        let fr = try catalog("fr")
        for (resource, english, french) in labels {
            // AppIntents requires Bundle.main. In SPM the catalogs live
            // in Bundle.module, so a remote host must have a readable
            // default, while the native bundle supplies translations.
            let data = try JSONEncoder().encode(resource)
            var restored = try JSONDecoder().decode(LocalizedStringResource.self, from: data)
            restored.locale = Locale(identifier: "en_US")
            XCTAssertEqual(String(localized: restored), english)
            XCTAssertEqual(en[restored.key], english)
            XCTAssertEqual(fr[restored.key], french)
        }
    }
}
