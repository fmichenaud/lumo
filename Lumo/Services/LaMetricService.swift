import Foundation

/// Une icône de la galerie LaMetric.
struct LaMetricIcon: Identifiable, Sendable, Hashable {
    let id: Int
    let name: String
    let type: Int   // 0 = statique, 1 = animée

    var isAnimated: Bool { type == 1 }

    /// URL de l'icône réelle en 8×8 (GIF si animée, PNG si statique).
    var assetURL: URL? {
        URL(string: "https://developer.lametric.com/content/apps/icon_thumbs/\(id)")
    }
}

/// Accès à la galerie d'icônes LaMetric (recherche + téléchargement).
enum LaMetricService {

    static let galleryURL = URL(string: "https://developer.lametric.com/icons")!

    /// Recherche d'icônes via l'endpoint interne de la galerie.
    static func search(term: String, page: Int = 0, count: Int = 60) async throws -> [LaMetricIcon] {
        var comps = URLComponents(string: "https://developer.lametric.com/api/v1/dev/preloadicons")!
        comps.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "category", value: ""),
            URLQueryItem(name: "search", value: term),
            URLQueryItem(name: "count", value: "\(count)"),
            URLQueryItem(name: "guest_icons", value: "true")
        ]
        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.icons.map {
            LaMetricIcon(id: $0.id, name: ($0.name ?? "Icône").trimmingCharacters(in: .whitespaces), type: $0.type ?? 0)
        }
    }

    /// Télécharge l'icône réelle 8×8 (octets bruts : GIF animé ou PNG statique).
    static func fetchIcon(id: String) async throws -> Data {
        guard let url = URL(string: "https://developer.lametric.com/content/apps/icon_thumbs/\(id)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private struct SearchResponse: Decodable {
        let icons: [IconDTO]
        struct IconDTO: Decodable {
            let id: Int
            let type: Int?
            let name: String?
        }
    }
}
