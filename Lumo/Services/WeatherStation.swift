import Foundation
import Combine

/// État météo partagé au niveau de l'app : persiste la ville, rafraîchit, et pousse sur l'afficheur.
/// Vit aussi longtemps que le process (donc continue en tâche de fond via la menu-bar).
@MainActor
final class WeatherStation: ObservableObject {
    @Published private(set) var locationLabel: String
    @Published private(set) var weather: WeatherNow?
    @Published private(set) var autoEnabled: Bool

    private var latitude: Double
    private var longitude: Double
    private weak var store: DeviceStore?
    private var task: Task<Void, Never>?
    private let defaults = UserDefaults.standard

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
        if let data = try? await LaMetricService.fetchIcon(id: condition.iconID),
           let gif = IconConverter.awtrixGIF(from: data) {
            try? await client.uploadIcon(id: condition.iconID, data: gif, ext: "gif")
        }
        var payload = PushPayload()
        payload.text = weather.tempText
        payload.icon = condition.iconID
        payload.color = "#FFFFFF"
        try? await client.upsertCustomApp(name: "weather", payload: payload)
        if switchTo { try? await client.switchApp(name: "weather") }
    }

    func setAuto(_ on: Bool) {
        autoEnabled = on
        defaults.set(on, forKey: "lumo.weather.auto")
        task?.cancel()
        task = nil
        if on { startAuto() }
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
