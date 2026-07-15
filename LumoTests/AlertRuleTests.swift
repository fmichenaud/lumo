import Testing
import Foundation
@testable import Lumo

struct AlertRuleTests {
    @Test func triggersAboveThreshold() {
        var rule = AlertRule()
        rule.comparison = .above
        rule.threshold = 90
        #expect(rule.isTriggered(value: 95))
        #expect(!rule.isTriggered(value: 90))
        #expect(!rule.isTriggered(value: 12))
    }

    @Test func triggersBelowThreshold() {
        var rule = AlertRule()
        rule.metric = .deviceBattery
        rule.comparison = .below
        rule.threshold = 20
        #expect(rule.isTriggered(value: 15))
        #expect(!rule.isTriggered(value: 20))
        #expect(!rule.isTriggered(value: 80))
    }

    @Test func generatedMessageWhenEmpty() {
        var rule = AlertRule()
        rule.metric = .macCPU
        #expect(rule.renderedMessage(value: 95).contains("95%"))
    }

    @Test func customMessageReplacesValue() {
        var rule = AlertRule()
        rule.metric = .macCPU
        rule.message = "Alerte : {value} !"
        #expect(rule.renderedMessage(value: 95) == "Alerte : 95% !")
    }

    @Test func conditionSummaryReadable() {
        var rule = AlertRule()
        rule.metric = .macCPU
        rule.comparison = .above
        rule.threshold = 90
        #expect(rule.conditionSummary().contains("> 90%"))
    }

    @Test func parsesNumbersFromConnectorText() {
        #expect(AlertRule.numericValue(from: "42") == 42)
        #expect(AlertRule.numericValue(from: "BTC 65432.10€") == 65432.10)
        #expect(AlertRule.numericValue(from: "1 234,5") == 1234.5)
        #expect(AlertRule.numericValue(from: "-3,2°") == -3.2)
        #expect(AlertRule.numericValue(from: "aucun nombre") == nil)
    }

    @Test func hexToRGB() {
        #expect(AlertsStation.rgb(fromHex: "#FF0000") == [255, 0, 0])
        #expect(AlertsStation.rgb(fromHex: "3DD68C") == [61, 214, 140])
    }
}
