import Testing
import Foundation
@testable import Lumo

struct ClaudeUsageTests {
    @Test func textBothMetrics() {
        #expect(ClaudeUsageStation.text(session: 59, weekly: 13, display: .both) == "CC 59% · 7j 13%")
        #expect(ClaudeUsageStation.text(session: 59, weekly: nil, display: .both) == "CC 59% · 7j —")
        #expect(ClaudeUsageStation.text(session: nil, weekly: nil, display: .both) == "")
    }

    @Test func textSingleMetric() {
        #expect(ClaudeUsageStation.text(session: 59, weekly: 13, display: .session) == "CC 59%")
        #expect(ClaudeUsageStation.text(session: 59, weekly: 13, display: .weekly) == "CC 7j 13%")
        #expect(ClaudeUsageStation.text(session: nil, weekly: 13, display: .session) == "")
    }

    @Test func colorThresholds() {
        #expect(ClaudeUsageStation.color(forPercent: 10) == "#3DD68C")
        #expect(ClaudeUsageStation.color(forPercent: 70) == "#FFC400")
        #expect(ClaudeUsageStation.color(forPercent: 95) == "#FF5555")
    }
}

struct StripeMRRTests {
    @Test func monthlyPlansPassThrough() {
        #expect(StripeStation.monthlyCents(unitAmount: 999, quantity: 1, interval: "month", intervalCount: 1) == 999)
        #expect(StripeStation.monthlyCents(unitAmount: 999, quantity: 3, interval: "month", intervalCount: 1) == 2997)
    }

    @Test func yearlyPlansDividedBy12() {
        #expect(StripeStation.monthlyCents(unitAmount: 12000, quantity: 1, interval: "year", intervalCount: 1) == 1000)
    }

    @Test func quarterlyPlans() {
        #expect(StripeStation.monthlyCents(unitAmount: 3000, quantity: 1, interval: "month", intervalCount: 3) == 1000)
    }

    @Test func weeklyAndDailyApproximations() {
        let weekly = StripeStation.monthlyCents(unitAmount: 100, quantity: 1, interval: "week", intervalCount: 1)
        #expect(weekly > 400 && weekly < 460)
        let daily = StripeStation.monthlyCents(unitAmount: 100, quantity: 1, interval: "day", intervalCount: 1)
        #expect(daily > 3000 && daily < 3100)
    }

    @Test func unknownIntervalIgnored() {
        #expect(StripeStation.monthlyCents(unitAmount: 100, quantity: 1, interval: "once", intervalCount: 1) == 0)
    }

    @Test func formatting() {
        #expect(StripeStation.format(1234.4) == "1234")
        #expect(StripeStation.format(42.5) == "42.50")
        #expect(StripeStation.symbol(for: "eur") == "€")
        #expect(StripeStation.symbol(for: "usd") == "$")
        #expect(StripeStation.symbol(for: "chf") == " CHF")
    }
}
