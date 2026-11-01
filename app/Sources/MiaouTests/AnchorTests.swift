import XCTest
@testable import Miaou

final class AnchorTests: XCTestCase {
    func testConsoleCostAcceptsDecimalSeparatorsAndZero() {
        XCTAssertEqual(ConsoleCost.parse("190.05"), 190.05)
        XCTAssertEqual(ConsoleCost.parse("190,05"), 190.05)
        XCTAssertEqual(ConsoleCost.parse(" 190,05\n"), 190.05)
        XCTAssertEqual(ConsoleCost.parse("0"), 0)
    }

    func testConsoleCostRejectsInvalidValues() {
        for text in ["", " ", "abc", "-1", "nan", "inf", "1e999", "1,2.3"] {
            XCTAssertNil(ConsoleCost.parse(text), text)
        }
    }

    func testAddAnchorRejectsInvalidCostsBeforeRunningCLI() {
        for cost in [-1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try MiaouCLI.addAnchor(cost: cost)) { error in
                guard case MiaouError.invalidAnchorCost = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testDashboardInheritsConfigurationEnvironment() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("miaou-environment-test-\(UUID().uuidString)")
        let configDirectory = root.appendingPathComponent("miaou")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        [display]
        currency = "EUR"
        [budget]
        monthly_usd = 255.0
        """.write(to: configDirectory.appendingPathComponent("config.toml"),
                  atomically: true, encoding: .utf8)

        // Set parent variables so the default CLI calls must inherit them.
        // UTC keeps the Console anchor and dashboard in the same month.
        let overrides = [
            "XDG_CONFIG_HOME": root.path,
            "VIBE_HOME": root.appendingPathComponent("vibe").path,
            "TZ": "UTC",
        ]
        let originalEnvironment = ProcessInfo.processInfo.environment
        defer {
            for key in overrides.keys {
                if let original = originalEnvironment[key] {
                    setenv(key, original, 1)
                } else {
                    unsetenv(key)
                }
            }
        }
        for (key, value) in overrides {
            setenv(key, value, 1)
        }
        var environment = originalEnvironment
        environment.merge(overrides) { _, override in override }
        do {
            try MiaouCLI.addAnchor(cost: 12.34, environment: environment)
            let report = try MiaouCLI.dashboard()
            XCTAssertEqual(report.currency, "€")
            XCTAssertEqual(report.budgetStatus.budget.monthlyUsd, 255.0)
            XCTAssertEqual(report.anchor?.cost, 12.34)
            XCTAssertEqual(report.budgetStatus.usedUsd, 12.34)
        } catch MiaouError.processFailed(let code) where code == 127 {
            throw XCTSkip("miaou not installed in the test environment")
        }
    }

    /// Exercise the app's CLI bridge without touching the user's ledger.
    func testAddAnchorRecordsCostAtCurrentTime() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("miaou-anchor-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var environment = ProcessInfo.processInfo.environment
        environment["XDG_CONFIG_HOME"] = root.path
        environment["VIBE_HOME"] = root.appendingPathComponent("vibe").path
        let startedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        do {
            try MiaouCLI.addAnchor(cost: 190.05, environment: environment)
        } catch MiaouError.processFailed(let code) where code == 127 {
            throw XCTSkip("miaou not installed in the test environment")
        }
        let finishedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        let ledger = try String(contentsOf: root.appendingPathComponent("miaou/calibration.toml"),
                                encoding: .utf8)
        XCTAssertTrue(ledger.contains("cost = 190.05\n"))
        XCTAssertEqual(ledger.components(separatedBy: "[[observations]]").count - 1, 1)
        let timestampLine = try XCTUnwrap(ledger.split(separator: "\n").first {
            $0.hasPrefix("at_ms = ")
        })
        let timestamp = try XCTUnwrap(Int(timestampLine.dropFirst("at_ms = ".count)))
        XCTAssertGreaterThanOrEqual(timestamp, startedAtMs)
        XCTAssertLessThanOrEqual(timestamp, finishedAtMs)
    }
}
