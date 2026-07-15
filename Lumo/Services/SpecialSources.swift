import Foundation
import Security

/// Sources « spéciales » des connecteurs : des services externes qui ne rentrent pas dans le
/// moule URL + chemin JSON (agrégation, Trousseau…). Le connecteur garde son cycle de vie
/// normal (galerie, éditeur, toggle, intervalle) ; seule la récupération de la valeur change.

/// Quota Claude Code — lit le token OAuth de Claude Code dans le Trousseau et interroge
/// l'endpoint d'usage (non documenté, celui de la commande /usage ; gestion d'erreur douce).
enum ClaudeQuotaSource {
    struct SourceError: Error { let message: String }

    private struct UsageResponse: Decodable {
        struct Bucket: Decodable { let utilization: Double? }
        let five_hour: Bucket?
        let seven_day: Bucket?
    }

    /// (texte affichable, session %, semaine %)
    static func fetch() async throws -> (value: String, session: Double?, weekly: Double?) {
        guard let token = keychainToken() else {
            throw SourceError(message: String(localized: "Token introuvable — ouvre Claude Code une fois, puis autorise Lumo dans le Trousseau."))
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 {
                throw SourceError(message: String(localized: "Token expiré — relance Claude Code pour le rafraîchir."))
            }
            throw SourceError(message: "HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        let session = decoded.five_hour?.utilization
        let weekly = decoded.seven_day?.utilization
        return (valueText(session: session, weekly: weekly), session, weekly)
    }

    /// Texte compact pour la matrice, ex. "59% · 7j 13%".
    static func valueText(session: Double?, weekly: Double?) -> String {
        let s = session.map { "\(Int($0))%" } ?? "—"
        let w = weekly.map { "\(Int($0))%" } ?? "—"
        return "\(s) · 7j \(w)"
    }

    /// Vert tant qu'on est large, orange quand ça chauffe, rouge près de la limite.
    static func color(forPercent p: Double) -> String {
        if p >= 90 { return "#FF5555" }
        if p >= 70 { return "#FFC400" }
        return "#3DD68C"
    }

    /// Token OAuth stocké par Claude Code (déclenche une autorisation Trousseau au 1er accès).
    static func keychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }
}

/// MRR Stripe — Stripe n'expose pas le MRR par API : on agrège les abonnements actifs
/// (paginé), normalisés au mois.
enum StripeMRRSource {
    struct SourceError: Error { let message: String }

    private struct SubscriptionsPage: Decodable {
        struct Subscription: Decodable {
            struct Items: Decodable { let data: [Item] }
            let items: Items
            let id: String
        }
        struct Item: Decodable {
            struct Price: Decodable {
                struct Recurring: Decodable {
                    let interval: String
                    let interval_count: Int?
                }
                let unit_amount: Int?
                let currency: String
                let recurring: Recurring?
            }
            let price: Price
            let quantity: Int?
        }
        let data: [Subscription]
        let has_more: Bool
    }

    /// (texte affichable, MRR en unités de devise)
    /// NB : les abonnements à plus de 10 items ne comptent que leurs 10 premiers items
    /// (limite de l'objet imbriqué Stripe) — cas rarissime.
    static func fetch(apiKey: String) async throws -> (value: String, mrr: Double) {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            throw SourceError(message: String(localized: "Clé API manquante"))
        }
        var totalCents = 0.0
        var currency: String?
        var startingAfter: String?
        for _ in 0..<10 {
            let page = try await fetchPage(apiKey: key, startingAfter: startingAfter)
            for sub in page.data {
                for item in sub.items.data {
                    guard let recurring = item.price.recurring else { continue }
                    currency = currency ?? item.price.currency
                    totalCents += monthlyCents(unitAmount: item.price.unit_amount ?? 0,
                                               quantity: item.quantity ?? 1,
                                               interval: recurring.interval,
                                               intervalCount: recurring.interval_count ?? 1)
                }
            }
            guard page.has_more, let last = page.data.last else { break }
            startingAfter = last.id
        }
        let mrr = totalCents / 100
        return ("\(format(mrr))\(symbol(for: currency ?? ""))", mrr)
    }

    private static func fetchPage(apiKey: String, startingAfter: String?) async throws -> SubscriptionsPage {
        var components = URLComponents(string: "https://api.stripe.com/v1/subscriptions")!
        components.queryItems = [URLQueryItem(name: "status", value: "active"),
                                 URLQueryItem(name: "limit", value: "100")]
        if let startingAfter {
            components.queryItems?.append(URLQueryItem(name: "starting_after", value: startingAfter))
        }
        var req = URLRequest(url: components.url!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401: throw SourceError(message: String(localized: "Clé API invalide"))
            case 403: throw SourceError(message: String(localized: "Clé sans accès aux abonnements — crée une clé restreinte avec « Subscriptions : lecture »"))
            default:  throw SourceError(message: "HTTP \(http.statusCode)")
            }
        }
        return try JSONDecoder().decode(SubscriptionsPage.self, from: data)
    }

    /// Montant mensuel en cents d'une ligne d'abonnement.
    static func monthlyCents(unitAmount: Int, quantity: Int, interval: String, intervalCount: Int) -> Double {
        let total = Double(unitAmount) * Double(max(1, quantity))
        let n = Double(max(1, intervalCount))
        switch interval {
        case "month": return total / n
        case "year":  return total / (12 * n)
        case "week":  return total * 4.345 / n     // 52.14 semaines / 12 mois
        case "day":   return total * 30.44 / n     // 365.25 jours / 12 mois
        default:      return 0
        }
    }

    static func format(_ amount: Double) -> String {
        amount >= 100 ? String(Int(amount.rounded())) : String(format: "%.2f", amount)
    }

    static func symbol(for currency: String) -> String {
        switch currency.lowercased() {
        case "eur": return "€"
        case "usd": return "$"
        case "gbp": return "£"
        case "":    return ""
        default:    return " " + currency.uppercased()
        }
    }
}
