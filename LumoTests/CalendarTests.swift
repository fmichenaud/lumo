import Testing
import Foundation
@testable import Lumo

/// Tests de la logique pure de l'intégration Calendrier (aucun accès EventKit réel :
/// tout est vérifié sur des `CalendarEventInfo` fabriqués).
struct CalendarStationTests {
    // Instant de référence arbitraire mais fixe pour des tests déterministes.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func event(inHours hours: Double, title: String = "Événement",
                       isAllDay: Bool = false) -> CalendarEventInfo {
        CalendarEventInfo(start: now.addingTimeInterval(hours * 3600), title: title, isAllDay: isAllDay)
    }

    // MARK: - Filtre « prochain événement dans les 24 h »

    @Test func prendLePlusProcheDansLes24h() {
        let events = [
            event(inHours: 6, title: "Plus tard"),
            event(inHours: 2, title: "Prochain"),
            event(inHours: 12, title: "Encore plus tard")
        ]
        #expect(CalendarStation.nextUpcoming(in: events, now: now)?.title == "Prochain")
    }

    @Test func ignoreLesEvenementsTouteLaJournee() {
        let events = [
            event(inHours: 1, title: "Férié", isAllDay: true),
            event(inHours: 3, title: "Réunion")
        ]
        #expect(CalendarStation.nextUpcoming(in: events, now: now)?.title == "Réunion")
    }

    @Test func ignoreLesEvenementsPassesOuTropLointains() {
        let events = [
            event(inHours: -1, title: "Passé"),
            event(inHours: 30, title: "Après-demain")
        ]
        #expect(CalendarStation.nextUpcoming(in: events, now: now) == nil)
    }

    @Test func evenementQuiCommenceMaintenantEstInclus() {
        let events = [event(inHours: 0, title: "Tout de suite")]
        #expect(CalendarStation.nextUpcoming(in: events, now: now)?.title == "Tout de suite")
    }

    @Test func aucunEvenementDonneNil() {
        #expect(CalendarStation.nextUpcoming(in: [], now: now) == nil)
    }

    // MARK: - Format « HH:mm Titre » pour l'écran 32×8

    /// Construit une date à heure fixe dans le fuseau courant (même fuseau que le formateur).
    private func date(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 15
        comps.hour = hour; comps.minute = minute
        return Calendar.current.date(from: comps)!
    }

    @Test func formatHeureEtTitre() {
        let info = CalendarEventInfo(start: date(hour: 14, minute: 30), title: "Réunion équipe", isAllDay: false)
        #expect(CalendarStation.displayText(for: info) == "14:30 Réunion équipe")
    }

    @Test func formatSur24Heures() {
        let info = CalendarEventInfo(start: date(hour: 9, minute: 5), title: "Café", isAllDay: false)
        #expect(CalendarStation.displayText(for: info) == "09:05 Café")
    }

    @Test func tronqueLesTitresTropLongs() {
        let long = String(repeating: "a", count: 40)
        let info = CalendarEventInfo(start: date(hour: 10, minute: 0), title: long, isAllDay: false)
        let text = CalendarStation.displayText(for: info, maxTitleLength: 24)
        #expect(text == "10:00 " + String(repeating: "a", count: 23) + "…")
    }

    @Test func titreCourtNonTronque() {
        let info = CalendarEventInfo(start: date(hour: 10, minute: 0), title: "Court", isAllDay: false)
        #expect(CalendarStation.displayText(for: info, maxTitleLength: 24) == "10:00 Court")
    }

    @Test func titreVideDonneJusteLHeure() {
        let info = CalendarEventInfo(start: date(hour: 8, minute: 15), title: "   ", isAllDay: false)
        #expect(CalendarStation.displayText(for: info) == "08:15")
    }
}
