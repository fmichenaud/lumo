import Foundation
import Combine

/// Les sous-sections d'un afficheur, affichées sous l'appareil dans la barre latérale.
enum DeviceSection: String, CaseIterable, Identifiable, Sendable {
    case compose, scenes, weather, data, integrations, alerts, draw, apps, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .compose:      return String(localized: "Composer")
        case .scenes:       return String(localized: "Scènes")
        case .weather:      return String(localized: "Météo")
        case .data:         return String(localized: "Données")
        case .integrations: return String(localized: "Intégrations")
        case .alerts:       return String(localized: "Alertes")
        case .draw:         return String(localized: "Dessin")
        case .apps:         return String(localized: "Apps")
        case .settings:     return String(localized: "Réglages")
        }
    }

    var icon: String {
        switch self {
        case .compose:      return "square.and.pencil"
        case .scenes:       return "bookmark.fill"
        case .weather:      return "cloud.sun.fill"
        case .data:         return "chart.bar.fill"
        case .integrations: return "antenna.radiowaves.left.and.right"
        case .alerts:       return "bell.badge.fill"
        case .draw:         return "paintbrush.pointed.fill"
        case .apps:         return "square.stack.3d.up.fill"
        case .settings:     return "slider.horizontal.3"
        }
    }

    /// Phrase d'explication affichée en tête de chaque section.
    var summary: String {
        switch self {
        case .compose:  return String(localized: "Crée un affichage permanent (texte, couleur, icône) ajouté à la rotation de l'écran.")
        case .scenes:   return String(localized: "Sauvegarde tes compositions et renvoie-les en 1 clic. Elles survivent au redémarrage du device.")
        case .weather:  return String(localized: "Affiche la météo de ta ville sur l'écran, avec mise à jour automatique possible.")
        case .alerts:   return String(localized: "Signaux ponctuels : une notification qui s'affiche puis disparaît, et les 3 LED témoins.")
        case .data:     return String(localized: "Affiche des graphiques, le cours d'une crypto ou les stats de ton Mac.")
        case .integrations: return String(localized: "Connecte n'importe quelle API (la tienne ou une externe) et affiche-la en direct.")
        case .draw:     return String(localized: "Dessine pixel par pixel et envoie ton image sur la matrice.")
        case .apps:     return String(localized: "Gère la rotation : affiche ou supprime les apps présentes sur le device.")
        case .settings: return String(localized: "Écran, luminosité, défilement, apps intégrées et lampe d'ambiance.")
        }
    }
}

/// Source de vérité des devices : persistance locale et sélection courante.
@MainActor
final class DeviceStore: ObservableObject {
    @Published var devices: [Device] = []
    @Published var selectedID: Device.ID?
    @Published var selectedSection: DeviceSection = .compose

    private let storageKey = "lumo.devices.v1"

    init() {
        load()
    }

    var selectedDevice: Device? {
        guard let id = selectedID else { return nil }
        return devices.first { $0.id == id }
    }

    func client(for device: Device) -> AwtrixClient {
        AwtrixClient(host: device.host)
    }

    /// Ajoute un device, ou met à jour son IP s'il est déjà connu (même uid).
    func add(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].host = device.host
        } else {
            devices.append(device)
        }
        if selectedID == nil { selectedID = device.id }
        save()
    }

    func merge(discovered: [Device]) {
        for device in discovered { add(device) }
    }

    func remove(_ device: Device) {
        devices.removeAll { $0.id == device.id }
        if selectedID == device.id { selectedID = devices.first?.id }
        save()
    }

    func rename(_ device: Device, to name: String) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].name = name
        save()
    }

    // MARK: - Persistance

    private func save() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Device].self, from: data) else { return }
        devices = saved
        selectedID = saved.first?.id
    }
}
