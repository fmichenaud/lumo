import Testing
import Foundation
@testable import Lumo

struct ClaudeQuotaSourceTests {
    @Test func valueText() {
        #expect(ClaudeQuotaSource.valueText(session: 59, weekly: 13) == "59% · 7j 13%")
        #expect(ClaudeQuotaSource.valueText(session: 59, weekly: nil) == "59% · 7j —")
        #expect(ClaudeQuotaSource.valueText(session: nil, weekly: nil) == "— · 7j —")
    }

    @Test func colorThresholds() {
        #expect(ClaudeQuotaSource.color(forPercent: 10) == "#3DD68C")
        #expect(ClaudeQuotaSource.color(forPercent: 70) == "#FFC400")
        #expect(ClaudeQuotaSource.color(forPercent: 95) == "#FF5555")
    }
}

struct StripeMRRSourceTests {
    @Test func monthlyPlansPassThrough() {
        #expect(StripeMRRSource.monthlyCents(unitAmount: 999, quantity: 1, interval: "month", intervalCount: 1) == 999)
        #expect(StripeMRRSource.monthlyCents(unitAmount: 999, quantity: 3, interval: "month", intervalCount: 1) == 2997)
    }

    @Test func yearlyPlansDividedBy12() {
        #expect(StripeMRRSource.monthlyCents(unitAmount: 12000, quantity: 1, interval: "year", intervalCount: 1) == 1000)
    }

    @Test func quarterlyPlans() {
        #expect(StripeMRRSource.monthlyCents(unitAmount: 3000, quantity: 1, interval: "month", intervalCount: 3) == 1000)
    }

    @Test func weeklyAndDailyApproximations() {
        let weekly = StripeMRRSource.monthlyCents(unitAmount: 100, quantity: 1, interval: "week", intervalCount: 1)
        #expect(weekly > 400 && weekly < 460)
        let daily = StripeMRRSource.monthlyCents(unitAmount: 100, quantity: 1, interval: "day", intervalCount: 1)
        #expect(daily > 3000 && daily < 3100)
    }

    @Test func unknownIntervalIgnored() {
        #expect(StripeMRRSource.monthlyCents(unitAmount: 100, quantity: 1, interval: "once", intervalCount: 1) == 0)
    }

    @Test func formatting() {
        #expect(StripeMRRSource.format(1234.4) == "1234")
        #expect(StripeMRRSource.format(42.5) == "42.50")
        #expect(StripeMRRSource.symbol(for: "eur") == "€")
        #expect(StripeMRRSource.symbol(for: "usd") == "$")
        #expect(StripeMRRSource.symbol(for: "chf") == " CHF")
    }
}

struct SpecialConnectorTests {
    @Test func oldConnectorsDecodeWithoutSpecial() throws {
        // Un connecteur sauvegardé avant l'ajout du champ `special` doit se décoder (nil).
        let old = ##"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Test","url":"https://x","auth":{"kind":"none","headerName":"Authorization","apiKey":"","bearerToken":"","authURL":"","tokenURL":"","clientID":"","clientSecret":"","scope":"","accessToken":"","helpURL":"","serviceName":""},"extraHeadersText":"","jsonPath":"","template":"{value}","fallbackText":"","colorHex":"#FFC400","icon":"","intervalSeconds":60,"enabled":false}"##
        let decoded = try JSONDecoder().decode(Connector.self, from: Data(old.utf8))
        #expect(decoded.special == nil)
        #expect(decoded.name == "Test")
    }

    @Test func specialTemplatesExist() {
        let titles = ConnectorTemplate.all.map(\.title)
        #expect(titles.contains("Quota Claude Code"))
        #expect(titles.contains("MRR Stripe"))
        let claude = ConnectorTemplate.all.first { $0.title == "Quota Claude Code" }!.build()
        #expect(claude.special == .claudeQuota)
        let stripe = ConnectorTemplate.all.first { $0.title == "MRR Stripe" }!.build()
        #expect(stripe.special == .stripeMRR)
        #expect(stripe.auth.kind == .bearer)
    }
}
