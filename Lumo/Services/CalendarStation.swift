import Foundation
import Combine
import EventKit

/// Événement minimal pour la logique pure (testable sans accès EventKit réel).
struct CalendarEventInfo {
    let start: Date
    let title: String
    let isAllDay: Bool
}

/// Intégration Calendrier : lit le prochain événement du Mac (EventKit, lecture seule)
/// et l'affiche sur la matrice via une app custom `calendar`.
/// Rafraîchit toutes les 5 min tant que le process vit (menu-bar comprise).
@MainActor
final class CalendarStation: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var nextEventText: String?
    @Published private(set) var lastError: String?

    private let eventStore = EKEventStore()
    private weak var store: DeviceStore?
    private var ticker: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private static let appName = "calendar"

    init() {
        enabled = defaults.bool(forKey: "lumo.calendar.on")
    }

    /// Relie le store (appelé au lancement) et démarre le rafraîchissement si activé.
    func attach(_ store: DeviceStore) {
        self.store = store
        if enabled { startTicker() }
    }

    /// Active/désactive : ON pousse tout de suite puis rafraîchit toutes les 5 min ;
    /// OFF retire l'app `calendar` de la rotation de l'afficheur.
    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: "lumo.calendar.on")
        ticker?.cancel()
        ticker = nil
        if on {
            startTicker()
        } else {
            nextEventText = nil
            Task { await removeFromDevice() }
        }
    }

    /// Cherche le prochain événement (dans les 24 h, hors « toute la journée »)
    /// et met l'afficheur à jour — supprime l'app s'il n'y a rien à venir.
    func refresh() async {
        guard await ensureAccess() else { return }
        let now = Date()
        let predicate = eventStore.predicateForEvents(withStart: now,
                                                      end: now.addingTimeInterval(24 * 3600),
                                                      calendars: nil)
        let events = eventStore.events(matching: predicate).map {
            CalendarEventInfo(start: $0.startDate, title: $0.title ?? "", isAllDay: $0.isAllDay)
        }
        if let next = Self.nextUpcoming(in: events, now: now) {
            let text = Self.displayText(for: next)
            nextEventText = text
            await push(text)
        } else {
            nextEventText = nil
            await removeFromDevice()
        }
    }

    // MARK: - Logique pure (testable)

    /// Prochain événement à venir dans les 24 h, en excluant les événements « toute la journée ».
    nonisolated static func nextUpcoming(in events: [CalendarEventInfo], now: Date) -> CalendarEventInfo? {
        let limit = now.addingTimeInterval(24 * 3600)
        return events
            .filter { !$0.isAllDay && $0.start >= now && $0.start <= limit }
            .min { $0.start < $1.start }
    }

    /// Texte court pour la matrice 32×8 : « HH:mm Titre » (le texte défile,
    /// mais on tronque les titres très longs pour garder un défilement raisonnable).
    nonisolated static func displayText(for event: CalendarEventInfo, maxTitleLength: Int = 24) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: event.start)
        var title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count > maxTitleLength {
            title = String(title.prefix(maxTitleLength - 1)) + "…"
        }
        return title.isEmpty ? time : "\(time) \(title)"
    }

    // MARK: - Accès EventKit

    /// Demande l'accès lecture au calendrier si nécessaire ; publie une erreur en cas de refus.
    private func ensureAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            lastError = nil
            return true
        case .notDetermined:
            let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
            lastError = granted ? nil : Self.deniedMessage
            return granted
        default:
            lastError = Self.deniedMessage
            return false
        }
    }

    private static var deniedMessage: String {
        String(localized: "Accès refusé — Réglages Système → Confidentialité → Calendriers")
    }

    // MARK: - Device

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            }
        }
    }

    private func push(_ text: String) async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host)
            .upsertCustomAppRaw(name: Self.appName,
                                json: ["text": text, "color": "#4DA6FF", "repeat": 1])
    }

    private func removeFromDevice() async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host).deleteCustomApp(name: Self.appName)
    }
}
