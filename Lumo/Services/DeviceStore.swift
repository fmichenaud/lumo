import Foundation
import Observation

/// Les sous-sections d'un afficheur, affichées sous l'appareil dans la barre latérale.
enum DeviceSection: String, CaseIterable, Identifiable, Sendable {
    case screen, studio, moments, device
    var id: String { rawValue }

    var title: String {
        switch self {
        case .screen:  return String(localized: "Écran")
        case .studio:  return String(localized: "Studio")
        case .moments: return String(localized: "Moments")
        case .device:  return String(localized: "Appareil")
        }
    }

    var icon: String {
        switch self {
        case .screen:  return "rectangle.stack.fill"
        case .studio:  return "paintpalette.fill"
        case .moments: return "bell.badge.fill"
        case .device:  return "slider.horizontal.3"
        }
    }
}

/// Source de vérité des devices : persistance locale et sélection courante.
@MainActor
@Observable
final class DeviceStore {
    var devices: [Device] = []
    var selectedID: Device.ID?
    var selectedSection: DeviceSection = .screen

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
