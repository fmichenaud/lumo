import Foundation
import Combine

/// Les sous-sections d'un afficheur, affichées sous l'appareil dans la barre latérale.
enum DeviceSection: String, CaseIterable, Identifiable, Sendable {
    case apps, compose, alerts, draw, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps:     return String(localized: "Apps")
        case .compose:  return String(localized: "Composer")
        case .alerts:   return String(localized: "Alertes")
        case .draw:     return String(localized: "Dessin")
        case .settings: return String(localized: "Réglages")
        }
    }

    var icon: String {
        switch self {
        case .apps:     return "square.stack.3d.up.fill"
        case .compose:  return "square.and.pencil"
        case .alerts:   return "bell.badge.fill"
        case .draw:     return "paintbrush.pointed.fill"
        case .settings: return "slider.horizontal.3"
        }
    }

    /// Phrase d'explication affichée en tête de chaque section.
    var summary: String {
        switch self {
        case .apps:     return String(localized: "Tout ce qui s'affiche à l'écran : active, configure et organise les apps de la rotation.")
        case .compose:  return String(localized: "Crée un affichage (texte, couleur, icône) et sauvegarde tes compositions en scènes.")
        case .alerts:   return String(localized: "Surveille des seuils (CPU, batterie, connecteurs…) et déclenche notification ou LED automatiquement.")
        case .draw:     return String(localized: "Dessine pixel par pixel et envoie ton image sur la matrice.")
        case .settings: return String(localized: "Écran, luminosité, défilement, durée par app et lampe d'ambiance.")
        }
    }
}

/// Source de vérité des devices : persistance locale et sélection courante.
@MainActor
final class DeviceStore: ObservableObject {
    @Published var devices: [Device] = []
    @Published var selectedID: Device.ID?
    @Published var selectedSection: DeviceSection = .apps

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
