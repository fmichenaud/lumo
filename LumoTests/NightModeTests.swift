import Testing
import Foundation
@testable import Lumo

struct NightModeTests {
    // MARK: - Plage nocturne simple (start < end)

    @Test func plageSimple() {
        // 1 h → 6 h
        #expect(NightModeStation.isNight(now: 3 * 60, start: 60, end: 6 * 60))
        #expect(!NightModeStation.isNight(now: 7 * 60, start: 60, end: 6 * 60))
        #expect(!NightModeStation.isNight(now: 0, start: 60, end: 6 * 60))
    }

    @Test func bornesInclusiveExclusive() {
        // Début inclus, fin exclue.
        #expect(NightModeStation.isNight(now: 60, start: 60, end: 6 * 60))
        #expect(!NightModeStation.isNight(now: 6 * 60, start: 60, end: 6 * 60))
    }

    // MARK: - Plage traversant minuit (start > end)

    @Test func plageTraversantMinuit() {
        // 23 h → 7 h
        let start = 23 * 60, end = 7 * 60
        #expect(NightModeStation.isNight(now: 23 * 60 + 30, start: start, end: end))  // 23 h 30
        #expect(NightModeStation.isNight(now: 0, start: start, end: end))             // minuit
        #expect(NightModeStation.isNight(now: 3 * 60, start: start, end: end))        // 3 h
        #expect(NightModeStation.isNight(now: 6 * 60 + 59, start: start, end: end))   // 6 h 59
        #expect(!NightModeStation.isNight(now: 7 * 60, start: start, end: end))       // 7 h pile
        #expect(!NightModeStation.isNight(now: 12 * 60, start: start, end: end))      // midi
        #expect(!NightModeStation.isNight(now: 22 * 60 + 59, start: start, end: end)) // 22 h 59
        #expect(NightModeStation.isNight(now: 23 * 60, start: start, end: end))       // 23 h pile
    }

    @Test func plageVideJamaisNuit() {
        // start == end → plage vide, jamais en nuit.
        #expect(!NightModeStation.isNight(now: 0, start: 8 * 60, end: 8 * 60))
        #expect(!NightModeStation.isNight(now: 8 * 60, start: 8 * 60, end: 8 * 60))
    }

    // MARK: - Conversion pourcentage → luminosité

    @Test func conversionPourcentage() {
        #expect(NightModeStation.brightnessValue(forPercent: 100) == 255)
        #expect(NightModeStation.brightnessValue(forPercent: 50) == 128)
        #expect(NightModeStation.brightnessValue(forPercent: 20) == 51)
        #expect(NightModeStation.brightnessValue(forPercent: 1) == 3)
        // Bornage : jamais 0 (écran resterait noir), et valeurs hors bornes ramenées.
        #expect(NightModeStation.brightnessValue(forPercent: 0) == 3)
        #expect(NightModeStation.brightnessValue(forPercent: 150) == 255)
    }

    // MARK: - Minutes depuis minuit

    @Test func minutesDepuisMinuit() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = cal.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 23, minute: 45))!
        #expect(NightModeStation.minutesSinceMidnight(date, calendar: cal) == 23 * 60 + 45)
        let midnight = cal.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 0, minute: 0))!
        #expect(NightModeStation.minutesSinceMidnight(midnight, calendar: cal) == 0)
    }
}
