import Foundation
import Observation

/// État météo partagé au niveau de l'app : persiste la ville, rafraîchit, et pousse sur l'afficheur.
/// Vit aussi longtemps que le process (donc continue en tâche de fond via la menu-bar).
@MainActor
@Observable
final class WeatherStation {
    private(set) var locationLabel: String
    private(set) var weather: WeatherNow?
    private(set) var autoEnabled: Bool

    private var latitude: Double
    private var longitude: Double
    private weak var store: DeviceStore?
    private var task: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    /// Icônes déjà téléversées, par afficheur ("host#icône") : inutile de re-télécharger
    /// chez LaMetric et de re-téléverser la même icône à chaque rafraîchissement.
    private var uploadedIcons: Set<String> = []

    init() {
        locationLabel = defaults.string(forKey: "lumo.weather.label") ?? ""
        latitude = defaults.double(forKey: "lumo.weather.lat")
        longitude = defaults.double(forKey: "lumo.weather.lon")
        autoEnabled = defaults.bool(forKey: "lumo.weather.auto")
    }

    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    /// Relie le store (appelé au lancement) et démarre l'auto-refresh si activé.
    func attach(_ store: DeviceStore) {
        self.store = store
        if autoEnabled { startAuto() }
        else if hasLocation { Task { await refresh() } }
    }

    func setLocation(_ place: GeoPlace) {
        locationLabel = place.label
        latitude = place.latitude
        longitude = place.longitude
        defaults.set(locationLabel, forKey: "lumo.weather.label")
        defaults.set(latitude, forKey: "lumo.weather.lat")
        defaults.set(longitude, forKey: "lumo.weather.lon")
        Task { await refresh() }
    }

    func refresh() async {
        guard hasLocation else { return }
        weather = try? await WeatherService.current(latitude: latitude, longitude: longitude)
    }

    /// Pousse la météo courante sur l'afficheur sélectionné (uploade l'icône si besoin).
    func push(switchTo: Bool) async {
        guard let weather, let device = store?.selectedDevice else { return }
        let client = AwtrixClient(host: device.host)
        let condition = weather.condition
        await ensureIcon(condition.iconID, host: device.host, client: client)
        var payload = PushPayload()
        payload.text = weather.tempText
        payload.icon = condition.iconID
        payload.color = "#FFFFFF"
        try? await client.upsertCustomApp(name: "weather", payload: payload)
        if switchTo { try? await client.switchApp(name: "weather") }
    }

    /// Active/désactive l'app météo sur l'afficheur : ON pousse tout de suite puis rafraîchit
    /// toutes les 15 min ; OFF retire l'app de la rotation.
    func setAuto(_ on: Bool) {
        autoEnabled = on
        defaults.set(on, forKey: "lumo.weather.auto")
        task?.cancel()
        task = nil
        if on { startAuto() } else { Task { await removeFromDevice() } }
    }

    /// Téléverse l'icône météo une seule fois par afficheur (elle reste en flash ensuite).
    private func ensureIcon(_ id: String, host: String, client: AwtrixClient) async {
        let key = "\(host)#\(id)"
        guard !uploadedIcons.contains(key) else { return }
        guard let data = try? await LaMetricService.fetchIcon(id: id),
              let gif = IconConverter.awtrixGIF(from: data) else { return }
        try? await client.uploadIcon(id: id, data: gif, ext: "gif")
        uploadedIcons.insert(key)
    }

    private func removeFromDevice() async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host).deleteCustomApp(name: "weather")
    }

    private func startAuto() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                await self?.push(switchTo: false)
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
            }
        }
    }
}
