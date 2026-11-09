import XCTest
@testable import Miaou

final class DecodeTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let sample: [String: Any] = [
        "generated_at_ms": 1790610000000,
        "currency": "€",
        "today": "2026-09-28",
        "current_month": "2026-09",
        "plan": ["plan_type": "chat", "plan_name": "INDIVIDUAL", "organization_kind": "S"] as [String: Any],
        "active_model": ["name": "mistral-large-4", "alias": "Le Chonk"] as [String: Any],
        "totals": ["requests": 100, "input_tokens": 1000, "output_tokens": 50,
                   "cached_input_tokens": 900, "total_tokens": 1050, "cost_usd": nil] as [String: Any?],
        "today_totals": ["requests": 10, "input_tokens": 100, "output_tokens": 5,
                          "cached_input_tokens": 90, "total_tokens": 105, "cost_usd": nil] as [String: Any?],
        "month_to_date": ["requests": 90, "input_tokens": 900, "output_tokens": 45,
                           "cached_input_tokens": 810, "total_tokens": 945, "cost_usd": nil] as [String: Any?],
        "budget_status": ["month": "2026-09", "used_usd": nil, "used_tokens": 945,
                          "used_requests": 90,
                          "budget": ["monthly_usd": 255.0, "overage_usd": nil,
                                     "overage_allowed": true, "monthly_tokens": nil]] as [String: Any?],
        "daily": [["key": "2026-09-28", "sessions": 4, "requests": 100,
                   "input_tokens": 1000, "output_tokens": 50,
                   "cached_input_tokens": 900, "total_tokens": 1050, "cost_usd": nil] as [String: Any?]],
        "monthly": [["key": "2026-09", "sessions": 4, "requests": 100,
                     "input_tokens": 1000, "output_tokens": 50,
                     "cached_input_tokens": 900, "total_tokens": 1050, "cost_usd": nil] as [String: Any?]],
        "projects": [["key": "github.com/edjubert/miaou", "sessions": 2, "requests": 40,
                      "input_tokens": 400, "output_tokens": 20,
                      "cached_input_tokens": 360, "total_tokens": 420, "cost_usd": nil,
                      "remote": "git@github.com:edjubert/miaou.git",
                      "worktrees": ["/Users/x/.cadencr/worktrees/miaou/feature-a",
                                    "/Users/x/.cadencr/worktrees/miaou/feature-b"]] as [String: Any?],
                     ["key": "plain-dir", "sessions": 1, "requests": 5,
                      "input_tokens": 50, "output_tokens": 5,
                      "cached_input_tokens": 45, "total_tokens": 55, "cost_usd": nil] as [String: Any?]],
        "sessions": [["session_id": "abcd1234-rest", "short_id": "abcd1234", "project": "dotfiles",
                      "title": "Fix the thing", "title_source": "manual", "active": true,
                      "subagent": false, "started_ms": 1790600000000,
                      "requests": 40, "input_tokens": 400, "output_tokens": 20,
                      "cached_input_tokens": 360, "total_tokens": 420, "cost_usd": nil] as [String: Any?]],
        "active": [["id": "85ed9e33", "age_ms": 120000,
                    "title": "Live one", "title_source": "manual"],
                   ["id": "61fe6adc", "age_ms": 9844595]] as [[String: Any]],
        "anchor": ["at_ms": 1790610000000, "cost": 190.05, "delta_usd": 0.42] as [String: Any],
    ]

    func testDashboardDecodes() throws {
        let data = try JSONSerialization.data(withJSONObject: sample)
        let report = try decoder.decode(DashboardReport.self, from: data)
        XCTAssertEqual(report.today, "2026-09-28")
        XCTAssertEqual(report.currency, "€")
        XCTAssertEqual(report.plan?.planName, "INDIVIDUAL")
        XCTAssertEqual(report.activeModel?.name, "mistral-large-4")
        XCTAssertTrue(report.activeModel?.isChonk == true)
        XCTAssertNil(report.budgetStatus.usedUsd)
        XCTAssertEqual(report.budgetStatus.usedTokens, 945)
        XCTAssertEqual(report.budgetStatus.budget.monthlyUsd, 255.0)
        XCTAssertEqual(report.daily.count, 1)
        XCTAssertEqual(report.daily[0].totalTokens, 1050)
        XCTAssertEqual(report.projects[0].key, "github.com/edjubert/miaou")
        XCTAssertEqual(report.projects[0].remote, "git@github.com:edjubert/miaou.git")
        XCTAssertEqual(report.projects[0].worktrees?.count, 2)
        XCTAssertEqual(report.projects[1].key, "plain-dir")
        XCTAssertNil(report.projects[1].remote)
        XCTAssertNil(report.projects[1].worktrees)
        XCTAssertEqual(report.sessions[0].shortId, "abcd1234")
        XCTAssertEqual(report.sessions[0].title, "Fix the thing")
        XCTAssertEqual(report.sessions[0].titleSource, "manual")
        XCTAssertTrue(report.sessions[0].isActive)
        XCTAssertFalse(report.sessions[0].subagent)
        XCTAssertEqual(report.active.count, 2)
        XCTAssertEqual(report.liveSessions.map(\.id), ["85ed9e33", "61fe6adc"])
        XCTAssertEqual(report.active[0].title, "Live one")
        XCTAssertEqual(report.active[0].titleSource, "manual")
        XCTAssertNil(report.active[1].titleSource)
        XCTAssertEqual(report.anchor?.cost, 190.05)
        XCTAssertEqual(report.anchor?.deltaUsd, 0.42)
        XCTAssertEqual(report.anchor?.atMs, 1_790_610_000_000)
    }

    /// An older CLI does not emit `title_source`/`active`: decoding must
    /// stay lenient and report the session as inactive.
    func testSessionRowDecodesWithoutTitleSourceOrActive() throws {
        var legacy = sample
        var sessions = legacy["sessions"] as! [[String: Any?]]
        var first = sessions[0]
        first.removeValue(forKey: "title_source")
        first.removeValue(forKey: "active")
        sessions[0] = first
        legacy["sessions"] = sessions
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let report = try decoder.decode(DashboardReport.self, from: data)
        XCTAssertNil(report.sessions[0].titleSource)
        XCTAssertFalse(report.sessions[0].isActive)
    }

    func testDashboardDecodesWithoutAnchor() throws {
        var withoutAnchor = sample
        withoutAnchor.removeValue(forKey: "anchor")
        let data = try JSONSerialization.data(withJSONObject: withoutAnchor)
        let report = try decoder.decode(DashboardReport.self, from: data)
        XCTAssertNil(report.anchor)
    }

    /// An older CLI does not emit `active_model`: decoding must stay
    /// lenient and report a non-chonk model.
    func testDashboardDecodesWithoutActiveModel() throws {
        var legacy = sample
        legacy.removeValue(forKey: "active_model")
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let report = try decoder.decode(DashboardReport.self, from: data)
        XCTAssertNil(report.activeModel)
    }

    func testEffectiveUsdRespectsOverageFlag() throws {
        let withOverage = BudgetReport(monthlyUsd: 255.0, overageUsd: 50.0,
                                      overageAllowed: true, monthlyTokens: nil)
        XCTAssertEqual(withOverage.effectiveUsd, 305.0)
        let without = BudgetReport(monthlyUsd: 255.0, overageUsd: 50.0,
                                   overageAllowed: false, monthlyTokens: nil)
        XCTAssertEqual(without.effectiveUsd, 255.0)
    }

    func testActiveSessionDoesNotExpireBasedOnLockAge() {
        var dashboard = dashboardFixture(usedUsd: nil)
        dashboard.active = [ActiveSessionReport(id: "a", ageMs: 600_000)]
        XCTAssertEqual(dashboard.liveSessions.map(\.id), ["a"])
    }

    func testTokenFormatting() {
        XCTAssertEqual(formatTokens(18_000_020), "18.0M")
        XCTAssertEqual(formatTokens(999), "999")
        XCTAssertEqual(formatTokens(1500), "1.5k")
        XCTAssertEqual(formatTokens(2_500_000_000), "2.5B")
    }

    private func dashboardFixture(usedUsd: Double?, currency: String = "€") -> DashboardReport {
        DashboardReport(
            generatedAtMs: 1,
            today: "2026-09-29",
            currentMonth: "2026-09",
            activeModel: nil,
            currency: currency,
            plan: nil,
            totals: TotalsReport(requests: 1, inputTokens: 1, outputTokens: 1,
                                 cachedInputTokens: 0, totalTokens: 2, costUsd: nil),
            todayTotals: TotalsReport(requests: 1, inputTokens: 1, outputTokens: 1,
                                     cachedInputTokens: 0, totalTokens: 2, costUsd: nil),
            monthToDate: TotalsReport(requests: 1, inputTokens: 1, outputTokens: 1,
                                      cachedInputTokens: 0, totalTokens: 2, costUsd: nil),
            budgetStatus: BudgetStatusReport(
                month: "2026-09",
                usedUsd: usedUsd,
                usedTokens: 18_000_020,
                usedRequests: 10,
                budget: BudgetReport(monthlyUsd: 255.0, overageUsd: nil,
                                     overageAllowed: true, monthlyTokens: nil)),
            anchor: nil,
            daily: [], monthly: [], projects: [], sessions: [],
            active: [])
    }

    func testBarTitleModes() {
        // No dashboard yet: loading dots.
        XCTAssertEqual(BarTitle.text(.percent, dashboard: nil), "…")

        let d = dashboardFixture(usedUsd: 68.75)
        XCTAssertEqual(BarTitle.text(.percent, dashboard: d), "27%")
        XCTAssertEqual(BarTitle.text(.cost, dashboard: d), "68.75 €")
        XCTAssertEqual(BarTitle.text(.both, dashboard: d), "68.75 € (27%)")

        // Without cost estimation, every mode falls back to month tokens.
        let noCost = dashboardFixture(usedUsd: nil)
        XCTAssertEqual(BarTitle.text(.percent, dashboard: noCost), "18.0M")
        XCTAssertEqual(BarTitle.text(.cost, dashboard: noCost), "18.0M")
        XCTAssertEqual(BarTitle.text(.both, dashboard: noCost), "18.0M")
    }

    func testBarTitleIgnoresLiveSessions() {
        var d = dashboardFixture(usedUsd: 68.75)
        d.active = [ActiveSessionReport(id: "s", ageMs: 1000)]
        XCTAssertEqual(BarTitle.text(.percent, dashboard: d), "27%")
    }

    /// End-to-end contract check against the real binary, when it is in PATH.
    func testLiveCLIDashboardDecodes() throws {
        do {
            let report = try MiaouCLI.dashboard()
            XCTAssertFalse(report.currentMonth.isEmpty)
            XCTAssertGreaterThanOrEqual(report.daily.count, 0)
        } catch MiaouError.processFailed {
            throw XCTSkip("miaou not runnable from the test environment")
        }
    }
}
