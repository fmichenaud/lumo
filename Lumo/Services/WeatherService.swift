import Foundation

/// Un lieu renvoyé par le géocodage Open-Meteo.
struct GeoPlace: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?

    var label: String {
        [name, admin1, country].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Condition météo : icône LaMetric associée + libellé FR.
struct WeatherCondition {
    let iconID: String
    let label: String

    /// Mapping des codes WMO (Open-Meteo) vers nos icônes météo.
    static func from(code: Int) -> WeatherCondition {
        switch code {
        case 0, 1:                       return .init(iconID: "2282", label: "Ensoleillé")
        case 2:                          return .init(iconID: "876", label: "Partiellement nuageux")
        case 3:                          return .init(iconID: "91", label: "Couvert")
        case 45, 48:                     return .init(iconID: "2154", label: "Brouillard")
        case 51, 53, 55, 56, 57:         return .init(iconID: "72",   label: "Bruine")
        case 61, 63, 65, 66, 67, 80, 81, 82: return .init(iconID: "72", label: "Pluie")
        case 71, 73, 75, 77, 85, 86:     return .init(iconID: "80",   label: "Neige")
        case 95, 96, 99:                 return .init(iconID: "11428", label: "Orage")
        default:                         return .init(iconID: "2283", label: "—")
        }
    }
}

/// Météo actuelle.
struct WeatherNow {
    let temperature: Double
    let code: Int

    var condition: WeatherCondition { WeatherCondition.from(code: code) }
    var tempText: String { "\(Int(temperature.rounded()))°" }
}

/// Source de données météo : Open-Meteo (gratuit, sans clé API).
enum WeatherService {

    static func geocode(_ query: String) async throws -> [GeoPlace] {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "fr"),
            URLQueryItem(name: "format", value: "json")
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return (try JSONDecoder().decode(GeoResponse.self, from: data)).results ?? []
    }

    static func current(latitude: Double, longitude: Double) async throws -> WeatherNow {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return WeatherNow(temperature: decoded.current.temperature_2m, code: decoded.current.weather_code)
    }

    private struct GeoResponse: Decodable { let results: [GeoPlace]? }
    private struct ForecastResponse: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        let current: Current
    }
}
