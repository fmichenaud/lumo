import Testing
import Foundation
@testable import Lumo

struct PomodoroFormatTests {
    @Test func formatMMSS() {
        #expect(PomodoroStation.timeText(0) == "00:00")
        #expect(PomodoroStation.timeText(5) == "00:05")
        #expect(PomodoroStation.timeText(59) == "00:59")
        #expect(PomodoroStation.timeText(60) == "01:00")
        #expect(PomodoroStation.timeText(25 * 60) == "25:00")
        #expect(PomodoroStation.timeText(45 * 60 + 7) == "45:07")
    }

    @Test func formatBeyondOneHour() {
        // Les minutes peuvent dépasser 59 (durée custom > 1 h).
        #expect(PomodoroStation.timeText(90 * 60) == "90:00")
    }

    @Test func negativeClampedToZero() {
        #expect(PomodoroStation.timeText(-3) == "00:00")
    }
}

struct PomodoroPercentTests {
    @Test func percentRemaining() {
        #expect(PomodoroStation.percentRemaining(remaining: 1500, total: 1500) == 100)
        #expect(PomodoroStation.percentRemaining(remaining: 750, total: 1500) == 50)
        #expect(PomodoroStation.percentRemaining(remaining: 0, total: 1500) == 0)
    }

    @Test func percentClampedAndSafe() {
        #expect(PomodoroStation.percentRemaining(remaining: 2000, total: 1500) == 100)
        #expect(PomodoroStation.percentRemaining(remaining: -5, total: 1500) == 0)
        #expect(PomodoroStation.percentRemaining(remaining: 10, total: 0) == 0)
    }
}

struct PomodoroColorTests {
    @Test func greenAboveTwentyPercent() {
        #expect(PomodoroStation.colorHex(forPercentRemaining: 100) == "#3DD68C")
        #expect(PomodoroStation.colorHex(forPercentRemaining: 50) == "#3DD68C")
        #expect(PomodoroStation.colorHex(forPercentRemaining: 20) == "#3DD68C")
    }

    @Test func orangeUnderTwentyPercent() {
        #expect(PomodoroStation.colorHex(forPercentRemaining: 19) == "#FFC400")
        #expect(PomodoroStation.colorHex(forPercentRemaining: 10) == "#FFC400")
    }

    @Test func redUnderTenPercent() {
        #expect(PomodoroStation.colorHex(forPercentRemaining: 9) == "#FF5555")
        #expect(PomodoroStation.colorHex(forPercentRemaining: 0) == "#FF5555")
    }
}

struct PomodoroMelodyTests {
    @Test func rtttlStructure() {
        // Format RTTTL : nom:défauts:notes (trois sections séparées par ':').
        let parts = PomodoroStation.endMelody.split(separator: ":")
        #expect(parts.count == 3)
        #expect(parts[1].contains("d=") && parts[1].contains("o=") && parts[1].contains("b="))
        #expect(!parts[2].isEmpty)
    }
}
