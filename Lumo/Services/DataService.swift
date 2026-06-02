import Foundation

/// Une crypto suivie.
struct Coin: Identifiable, Hashable {
    let id: String        // id CoinGecko (bitcoin, ethereum…)
    let symbol: String    // BTC, ETH…
    var name: String { symbol }
}

/// Sources de données externes (crypto via CoinGecko, gratuit/sans clé).
enum DataService {
    static let coins: [Coin] = [
        Coin(id: "bitcoin", symbol: "BTC"),
        Coin(id: "ethereum", symbol: "ETH"),
        Coin(id: "solana", symbol: "SOL"),
        Coin(id: "dogecoin", symbol: "DOGE")
    ]

    static func cryptoPrice(id: String, currency: String) async throws -> Double {
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=\(currency)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode([String: [String: Double]].self, from: data)
        return decoded[id]?[currency] ?? 0
    }
}
