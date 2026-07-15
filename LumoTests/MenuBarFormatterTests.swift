import Testing
import Foundation
@testable import Lumo

struct MenuBarClaudeLineTests {
    @Test func bothMetrics() {
        #expect(MenuBarView.claudeLine(session: 59, weekly: 13) == "Claude : session 59 % · semaine 13 %")
    }

    @Test func sessionOnly() {
        #expect(MenuBarView.claudeLine(session: 42, weekly: nil) == "Claude : session 42 %")
    }

    @Test func weeklyOnly() {
        #expect(MenuBarView.claudeLine(session: nil, weekly: 88) == "Claude : semaine 88 %")
    }

    @Test func roundsToNearestInt() {
        #expect(MenuBarView.claudeLine(session: 59.6, weekly: 12.4) == "Claude : session 60 % · semaine 12 %")
    }
}

struct MenuBarStripeLineTests {
    @Test func bothValues() {
        #expect(MenuBarView.stripeLine(mrr: "1234€", total: "12345€") == "MRR 1234€ · Total 12345€")
    }

    @Test func mrrOnly() {
        #expect(MenuBarView.stripeLine(mrr: "1234€", total: nil) == "MRR 1234€")
    }

    @Test func totalOnly() {
        #expect(MenuBarView.stripeLine(mrr: nil, total: "99$") == "Total 99$")
    }

    @Test func nothing() {
        #expect(MenuBarView.stripeLine(mrr: nil, total: nil) == "")
    }
}
