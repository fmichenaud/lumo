import Foundation
import Observation

/// Action appliquée à l'afficheur pendant la plage nocturne.
enum NightAction: String, CaseIterable, Sendable {
    case powerOff  // éteindre complètement l'écran
    case dim       // réduire la luminosité à un pourcentage configurable
}

/// Mode nuit programmé : à l'entrée dans la plage horaire, éteint l'écran ou réduit
/// la luminosité ; à la sortie, restaure l'état précédent. Edge-triggered : une seule
/// requête par transition (pas de renvoi à chaque tick). Gère les plages qui
/// traversent minuit (ex. 23 h → 7 h). Vit aussi longtemps que le process.
@MainActor
@Observable
final class NightModeStation {
    private(set) var enabled: Bool
    private(set) var startMinutes: Int   // minutes depuis minuit
    private(set) var endMinutes: Int     // minutes depuis minuit
    private(set) var action: NightAction
    private(set) var dimPercent: Int     // 1…100, utilisé si action == .dim

    /// Vrai si l'action nocturne est actuellement appliquée sur le device.
    private(set) var applied: Bool

    private weak var store: DeviceStore?
    private var task: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    init() {
        enabled = defaults.bool(forKey: "lumo.night.enabled")
        startMinutes = defaults.object(forKey: "lumo.night.start") as? Int ?? 23 * 60
        endMinutes = defaults.object(forKey: "lumo.night.end") as? Int ?? 7 * 60
        action = NightAction(rawValue: defaults.string(forKey: "lumo.night.action") ?? "") ?? .powerOff
        dimPercent = defaults.object(forKey: "lumo.night.dimPercent") as? Int ?? 20
        applied = defaults.bool(forKey: "lumo.night.applied")
    }

    /// Relie le store (appelé au lancement) et démarre la vérification périodique (60 s).
    func attach(_ store: DeviceStore) {
        self.store = store
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.evaluate()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    // MARK: - Réglages (persistés, ré-évaluent immédiatement)

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: "lumo.night.enabled")
        Task { await evaluate() }
    }

    func setStart(minutes: Int) {
        startMinutes = minutes
        defaults.set(minutes, forKey: "lumo.night.start")
        Task { await evaluate() }
    }

    func setEnd(minutes: Int) {
        endMinutes = minutes
        defaults.set(minutes, forKey: "lumo.night.end")
        Task { await evaluate() }
    }

    /// Change l'action ; si le mode nuit est déjà appliqué, restaure d'abord avec
    /// l'ancienne action pour ne pas laisser le device dans un état incohérent.
    func setAction(_ newAction: NightAction) {
        let previous = action
        action = newAction
        defaults.set(newAction.rawValue, forKey: "lumo.night.action")
        Task {
            if applied, let client = currentClient() {
                await restore(client, using: previous)
                setApplied(false)
            }
            await evaluate()
        }
    }

    func setDimPercent(_ percent: Int) {
        dimPercent = max(1, min(100, percent))
        defaults.set(dimPercent, forKey: "lumo.night.dimPercent")
        Task {
            // Si la nuit est déjà appliquée en mode « luminosité réduite », met à jour la valeur.
            if applied, action == .dim, let client = currentClient() {
                try? await client.setBrightness(Self.brightnessValue(forPercent: dimPercent))
            }
        }
    }

    // MARK: - Logique pure (testable)

    /// Vrai si `now` (minutes depuis minuit) tombe dans la plage [start, end),
    /// y compris quand la plage traverse minuit (start > end). Plage vide si start == end.
    nonisolated static func isNight(now: Int, start: Int, end: Int) -> Bool {
        guard start != end else { return false }
        if start < end { return now >= start && now < end }
        return now >= start || now < end
    }

    /// Convertit un pourcentage (1…100) en luminosité AWTRIX (1…255).
    nonisolated static func brightnessValue(forPercent percent: Int) -> Int {
        let clamped = max(1, min(100, percent))
        return max(1, Int((Double(clamped) / 100.0 * 255.0).rounded()))
    }

    /// Minutes écoulées depuis minuit pour une date donnée.
    nonisolated static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - Évaluation edge-triggered

    /// Compare l'état voulu (nuit ou pas) à l'état appliqué et n'agit qu'aux transitions.
    private func evaluate() async {
        guard let client = currentClient() else { return }
        let now = Self.minutesSinceMidnight(Date())
        let shouldBeNight = enabled && Self.isNight(now: now, start: startMinutes, end: endMinutes)
        guard shouldBeNight != applied else { return }

        if shouldBeNight {
            await apply(client)
            setApplied(true)
        } else {
            await restore(client, using: action)
            setApplied(false)
        }
    }

    /// Entrée en nuit : mémorise l'état actuel puis applique l'action choisie.
    private func apply(_ client: AwtrixClient) async {
        switch action {
        case .powerOff:
            try? await client.setPower(false)
        case .dim:
            // Mémorise la luminosité actuelle pour la restaurer au matin.
            if let settings = try? await client.fetchSettings(), let bri = settings.BRI {
                defaults.set(bri, forKey: "lumo.night.savedBrightness")
            }
            try? await client.setBrightness(Self.brightnessValue(forPercent: dimPercent))
        }
    }

    /// Sortie de nuit : restaure l'état d'avant (rallume ou remet la luminosité mémorisée).
    private func restore(_ client: AwtrixClient, using action: NightAction) async {
        switch action {
        case .powerOff:
            try? await client.setPower(true)
        case .dim:
            let saved = defaults.object(forKey: "lumo.night.savedBrightness") as? Int ?? 128
            try? await client.setBrightness(saved)
        }
    }

    private func setApplied(_ value: Bool) {
        applied = value
        defaults.set(value, forKey: "lumo.night.applied")
    }

    private func currentClient() -> AwtrixClient? {
        guard let device = store?.selectedDevice else { return nil }
        return AwtrixClient(host: device.host)
    }
}
