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

    @Test func countdownFormats() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(ClaudeQuotaSource.countdown(to: now.addingTimeInterval(-60), from: now) == "0min")
        #expect(ClaudeQuotaSource.countdown(to: now.addingTimeInterval(30), from: now) == "1min")
        #expect(ClaudeQuotaSource.countdown(to: now.addingTimeInterval(8 * 60), from: now) == "8min")
        #expect(ClaudeQuotaSource.countdown(to: now.addingTimeInterval(2 * 3600 + 19 * 60), from: now) == "2h19")
        #expect(ClaudeQuotaSource.countdown(to: now.addingTimeInterval(3 * 3600 + 5 * 60), from: now) == "3h05")
        #expect(ClaudeQuotaSource.countdown(to: now.addingTimeInterval(28 * 3600), from: now) == "1j 4h")
    }

    @Test func parsesISO8601WithAndWithoutFraction() {
        // Format réellement renvoyé par l'API (6 décimales, décalage +00:00) : la seconde
        // près suffit, la fraction peut être tronquée selon le chemin de repli.
        let withFraction = ClaudeQuotaSource.parseDate("2026-07-22T13:39:59.974707+00:00")
        #expect(withFraction.map { abs($0.timeIntervalSince1970 - 1_784_727_599) < 1 } == true)
        #expect(ClaudeQuotaSource.parseDate("2026-07-22T13:39:59Z") == Date(timeIntervalSince1970: 1_784_727_599))
        #expect(ClaudeQuotaSource.parseDate("pas une date") == nil)
    }

    @Test func templateTokens() {
        let quota = ClaudeQuotaSource.Quota(session: 42, weekly: 60,
                                            sessionReset: Date(timeIntervalSince1970: 8340),
                                            weeklyReset: Date(timeIntervalSince1970: 100_800))
        let tokens = ClaudeQuotaSource.tokens(quota, now: Date(timeIntervalSince1970: 0))
        #expect(tokens["session"] == "42%")
        #expect(tokens["week"] == "60%")
        #expect(tokens["reset"] == "2h19")
        #expect(tokens["weekReset"] == "1j 4h")

        var connector = Connector(template: "CC {session} · {reset} · 7j {week}")
        #expect(connector.renderedText(value: "x", tokens: tokens) == "CC 42% · 2h19 · 7j 60%")
        connector.template = "CC {value}"
        #expect(connector.renderedText(value: "42% · 7j 60%", tokens: tokens) == "CC 42% · 7j 60%")
    }
}

struct ConnectorColorTests {
    @Test func claudeQuotaDefaultsToLevelColor() {
        var claude = Connector()
        claude.special = .claudeQuota
        #expect(claude.usesLevelColor)
        #expect(claude.supportsLevelColor)
    }

    @Test func chosenColorWinsOnceLevelColorIsOff() {
        var claude = Connector(colorHex: "#41BDF5")
        claude.special = .claudeQuota
        claude.levelColor = false
        #expect(!claude.usesLevelColor)
    }

    @Test func plainConnectorsAlwaysUseTheirColor() {
        let api = Connector(colorHex: "#FFC400")
        #expect(!api.usesLevelColor)
        #expect(!api.supportsLevelColor)
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

struct StripeTotalSourceTests {
    @Test func salesAndRefundsCount() {
        #expect(StripeTotalSource.countsTowardTotal(type: "charge"))
        #expect(StripeTotalSource.countsTowardTotal(type: "payment"))
        #expect(StripeTotalSource.countsTowardTotal(type: "refund"))
        #expect(StripeTotalSource.countsTowardTotal(type: "payment_refund"))
    }

    @Test func payoutsAndFeesExcluded() {
        #expect(!StripeTotalSource.countsTowardTotal(type: "payout"))
        #expect(!StripeTotalSource.countsTowardTotal(type: "stripe_fee"))
        #expect(!StripeTotalSource.countsTowardTotal(type: "adjustment"))
        #expect(!StripeTotalSource.countsTowardTotal(type: "transfer"))
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
        let total = ConnectorTemplate.all.first { $0.title == "Gain total Stripe" }!.build()
        #expect(total.special == .stripeTotal)
        #expect(total.isStripe)
    }
}
