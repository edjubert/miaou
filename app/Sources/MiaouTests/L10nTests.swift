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
}
