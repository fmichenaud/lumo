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

    // MARK: - Rétrocompatibilité du décodage

    @Test func decodesLegacyRuleWithoutTriggerFields() throws {
        // JSON d'une règle persistée avant l'ajout des déclencheurs planifiés.
        let json = """
        {"id":"6F9A2C4E-1B3D-4E5F-8A7B-9C0D1E2F3A4B","metric":"macCPU",
         "comparison":"above","threshold":90,"message":"Alerte : {value}",
         "colorHex":"#FF5555","icon":"","sound":"","indicator":2,"enabled":true}
        """
        let rule = try JSONDecoder().decode(AlertRule.self, from: Data(json.utf8))
        #expect(rule.trigger == .threshold)
        #expect(rule.scheduleDays.isEmpty)
        #expect(rule.switchToApp.isEmpty)
        #expect(rule.metric == .macCPU)
        #expect(rule.threshold == 90)
        #expect(rule.indicator == 2)
        #expect(rule.message == "Alerte : {value}")
        #expect(rule.id.uuidString == "6F9A2C4E-1B3D-4E5F-8A7B-9C0D1E2F3A4B")
    }

    @Test func scheduleRuleRoundTripsThroughJSON() throws {
        var rule = AlertRule()
        rule.trigger = .schedule
        rule.scheduleMinutes = 9 * 60
        rule.scheduleDays = [2, 4, 6]
        rule.switchToApp = "weather"
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(AlertRule.self, from: data)
        #expect(decoded == rule)
    }

    // MARK: - Règles planifiées : résumé et message

    @Test func scheduleSummaryEveryDay() {
        var rule = AlertRule()
        rule.trigger = .schedule
        rule.scheduleMinutes = 9 * 60
        #expect(rule.conditionSummary() == "Tous les jours à 09:00")
    }

    @Test func scheduleSummarySpecificDays() {
        var rule = AlertRule()
        rule.trigger = .schedule
        rule.scheduleMinutes = 18 * 60 + 30
        rule.scheduleDays = [2, 3, 6]   // lundi, mardi, vendredi
        #expect(rule.conditionSummary() == "Lun, mar, ven à 18:30")
    }

    @Test func scheduleMessageUsedVerbatim() {
        var rule = AlertRule()
        rule.trigger = .schedule
        rule.message = "Météo : consulte l'écran"
        #expect(rule.renderedMessage(value: 0) == "Météo : consulte l'écran")
    }

    @Test func scheduleEmptyMessageFallsBackToTriggerName() {
        var rule = AlertRule()
        rule.trigger = .schedule
        rule.scheduleMinutes = 9 * 60
        #expect(rule.renderedMessage(value: 0).contains("09:00"))
        #expect(!rule.renderedMessage(value: 0).isEmpty)
    }

    // MARK: - Franchissement horaire (logique pure du moteur)

    @Test func scheduleFiresWhenCrossingTime() {
        // 08:59:5x → 09:00:0x : franchissement de 09:00.
        #expect(AlertsStation.scheduleShouldFire(
            nowMinutes: 540, lastTickMinutes: 539, scheduleMinutes: 540,
            weekday: 3, allowedDays: [], alreadyFiredToday: false))
        // Réveil du Mac : dernier tick à 08:30, on est 09:07 → rattrapage du même jour.
        #expect(AlertsStation.scheduleShouldFire(
            nowMinutes: 547, lastTickMinutes: 510, scheduleMinutes: 540,
            weekday: 3, allowedDays: [], alreadyFiredToday: false))
    }

    @Test func scheduleDoesNotFireBeforeOrLongAfter() {
        // Pas encore l'heure.
        #expect(!AlertsStation.scheduleShouldFire(
            nowMinutes: 539, lastTickMinutes: 538, scheduleMinutes: 540,
            weekday: 3, allowedDays: [], alreadyFiredToday: false))
        // L'heure est passée sans franchissement entre les deux ticks.
        #expect(!AlertsStation.scheduleShouldFire(
            nowMinutes: 600, lastTickMinutes: 599, scheduleMinutes: 540,
            weekday: 3, allowedDays: [], alreadyFiredToday: false))
    }

    @Test func scheduleFiresOnlyOncePerDay() {
        #expect(!AlertsStation.scheduleShouldFire(
            nowMinutes: 540, lastTickMinutes: 539, scheduleMinutes: 540,
            weekday: 3, allowedDays: [], alreadyFiredToday: true))
    }

    @Test func scheduleRespectsAllowedDays() {
        // Mercredi (4) autorisé, on est mardi (3) → rien.
        #expect(!AlertsStation.scheduleShouldFire(
            nowMinutes: 540, lastTickMinutes: 539, scheduleMinutes: 540,
            weekday: 3, allowedDays: [4], alreadyFiredToday: false))
        // On est mercredi → déclenche.
        #expect(AlertsStation.scheduleShouldFire(
            nowMinutes: 540, lastTickMinutes: 539, scheduleMinutes: 540,
            weekday: 4, allowedDays: [4], alreadyFiredToday: false))
    }

    @Test func scheduleHandlesMidnightWrap() {
        // 23:59 → 00:00, règle à minuit : le jour vient de changer, on déclenche.
        #expect(AlertsStation.scheduleShouldFire(
            nowMinutes: 0, lastTickMinutes: 1439, scheduleMinutes: 0,
            weekday: 5, allowedDays: [], alreadyFiredToday: false))
        // Même franchissement mais règle déjà tirée « aujourd'hui » → rien.
        #expect(!AlertsStation.scheduleShouldFire(
            nowMinutes: 0, lastTickMinutes: 1439, scheduleMinutes: 0,
            weekday: 5, allowedDays: [], alreadyFiredToday: true))
        // Après minuit, un horaire de la veille (23:55) n'est pas rattrapé.
        #expect(!AlertsStation.scheduleShouldFire(
            nowMinutes: 10, lastTickMinutes: 1439, scheduleMinutes: 1435,
            weekday: 5, allowedDays: [], alreadyFiredToday: false))
        // Le nouveau jour compte pour les jours autorisés.
        #expect(!AlertsStation.scheduleShouldFire(
            nowMinutes: 0, lastTickMinutes: 1439, scheduleMinutes: 0,
            weekday: 5, allowedDays: [4], alreadyFiredToday: false))
    }

    @Test func scheduleFirstTickDoesNotCatchUp() {
        // Premier tick (app lancée à 15:00) : une règle de 09:00 déjà passée ne tire pas.
        #expect(!AlertsStation.scheduleShouldFire(
            nowMinutes: 900, lastTickMinutes: nil, scheduleMinutes: 540,
            weekday: 3, allowedDays: [], alreadyFiredToday: false))
        // Sauf si on démarre pile à la minute prévue.
        #expect(AlertsStation.scheduleShouldFire(
            nowMinutes: 540, lastTickMinutes: nil, scheduleMinutes: 540,
            weekday: 3, allowedDays: [], alreadyFiredToday: false))
    }
}
