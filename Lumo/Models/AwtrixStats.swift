import Foundation

/// Réponse de GET /api/stats — état temps réel du device.
struct AwtrixStats: Codable, Sendable {
    var bat: Int?
    var lux: Int?
    var ram: Int?
    var bri: Int?
    var temp: Double?
    var hum: Double?
    var uptime: Int?
    var wifiSignal: Int?
    var messages: Int?
    var version: String?
    var app: String?
    var uid: String?
    var matrix: Bool?

    /// Vrai si l'appareil est bien un AWTRIX (et pas un autre objet sur le réseau).
    var isAwtrix: Bool {
        (uid?.lowercased().contains("awtrix") ?? false) || matrix == true
    }

    enum CodingKeys: String, CodingKey {
        case bat, lux, ram, bri, temp, hum, uptime, messages, version, app, uid, matrix
        case wifiSignal = "wifi_signal"
    }
}
