import XCTest
@testable import VibeGod

final class DecodeTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func testBudgetReportDecodes() throws {
        let json = """
        {
          "month": "2026-09",
          "used_usd": 12.5,
          "used_tokens": 18000020,
          "used_requests": 123,
          "budget": {
            "monthly_usd": 255.0,
            "overage_usd": null,
            "overage_allowed": true,
            "monthly_tokens": null
          },
          "effective_usd": 255.0,
          "remaining_usd": 242.5,
          "in_overage_usd": null,
          "over_limit_usd": null,
          "over": false
        }
        """
        let report = try decoder.decode(BudgetReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.month, "2026-09")
        XCTAssertEqual(report.usedUsd, 12.5)
        XCTAssertEqual(report.usedTokens, 18_000_020)
        XCTAssertEqual(report.budget.monthlyUsd, 255.0)
        XCTAssertTrue(report.budget.overageAllowed)
        XCTAssertNil(report.inOverageUsd)
        XCTAssertFalse(report.over)
    }

    func testBudgetReportWithoutCost() throws {
        let json = """
        {
          "month": "2026-09",
          "used_usd": null,
          "used_tokens": 500,
          "used_requests": 2,
          "budget": {"monthly_usd": null, "overage_usd": null,
                     "overage_allowed": false, "monthly_tokens": 1000},
          "effective_usd": null,
          "remaining_usd": null,
          "in_overage_usd": null,
          "over_limit_usd": null,
          "over": false
        }
        """
        let report = try decoder.decode(BudgetReport.self, from: Data(json.utf8))
        XCTAssertNil(report.usedUsd)
        XCTAssertEqual(report.budget.monthlyTokens, 1000)
        XCTAssertFalse(report.budget.overageAllowed)
    }

    func testTodayReportDecodes() throws {
        let json = """
        {
          "date": "2026-09-28",
          "totals": {
            "requests": 10,
            "input_tokens": 1000,
            "output_tokens": 50,
            "cached_input_tokens": 900,
            "total_tokens": 1050,
            "cost_usd": null
          }
        }
        """
        let report = try decoder.decode(TodayReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.totals.requests, 10)
        XCTAssertEqual(report.totals.cachedInputTokens, 900)
        XCTAssertEqual(report.totals.totalTokens, 1050)
        XCTAssertNil(report.totals.costUsd)
    }

    func testTokenFormatting() {
        XCTAssertEqual(formatTokens(18_000_020), "18.0M")
        XCTAssertEqual(formatTokens(999), "999")
        XCTAssertEqual(formatTokens(1500), "1.5k")
        XCTAssertEqual(formatTokens(2_500_000_000), "2.5B")
    }
}
