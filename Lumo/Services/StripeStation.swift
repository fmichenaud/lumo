import Foundation
import Combine

/// Intégration Stripe : calcule le MRR (revenu mensuel récurrent) en agrégeant les
/// abonnements actifs, normalisés au mois, et l'affiche sur la matrice.
/// Stripe n'expose pas le MRR via l'API : on le reconstitue depuis /v1/subscriptions.
@MainActor
final class StripeStation: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var apiKey: String
    @Published private(set) var mrr: Double?          // en unités de la devise (pas en cents)
    @Published private(set) var currency: String?     // "eur", "usd"…
    @Published private(set) var lastError: String?

    private weak var store: DeviceStore?
    private var ticker: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    init() {
        enabled = defaults.bool(forKey: "lumo.stripe.on")
        apiKey = defaults.string(forKey: "lumo.stripe.key") ?? ""
    }

    func attach(_ store: DeviceStore) {
        self.store = store
        if enabled && !apiKey.isEmpty { startTicker() }
    }

    var summaryText: String? {
        guard let mrr, let currency else { return nil }
        return "MRR \(Self.format(mrr))\(Self.symbol(for: currency))"
    }

    // MARK: - Réglages

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: "lumo.stripe.on")
        if on {
            startTicker()
            Task { await refresh() }
        } else {
            ticker?.cancel(); ticker = nil
            Task { await remove() }
        }
    }

    func setAPIKey(_ key: String) {
        apiKey = key.trimmingCharacters(in: .whitespaces)
        defaults.set(apiKey, forKey: "lumo.stripe.key")
        if enabled && !apiKey.isEmpty { Task { await refresh() } }
    }

    // MARK: - Boucle

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 1_800_000_000_000)   // 30 min
            }
        }
    }

    func refresh() async {
        guard !apiKey.isEmpty else {
            lastError = String(localized: "Clé API manquante")
            return
        }
        do {
            let (total, cur) = try await computeMRR()
            mrr = total
            currency = cur
            lastError = nil
            if enabled { await push() }
        } catch let error as StripeError {
            lastError = error.message
        } catch {
            lastError = String(localized: "Échec réseau")
        }
    }

    private func push() async {
        guard let device = store?.selectedDevice, let text = summaryText else { return }
        // Violet Stripe, texte défilant une fois en entier.
        let json: [String: Any] = ["text": text, "color": "#8A7DFF", "repeat": 1]
        try? await AwtrixClient(host: device.host).upsertCustomAppRaw(name: "mrr", json: json)
    }

    private func remove() async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host).deleteCustomApp(name: "mrr")
    }

    // MARK: - Calcul du MRR

    struct StripeError: Error { let message: String }

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

    /// Somme les abonnements actifs, page par page (max 10 pages de 100).
    /// NB : les abonnements à plus de 10 items ne sont comptés que sur leurs 10 premiers
    /// items (limite de l'objet imbriqué Stripe) — cas rarissime.
    private func computeMRR() async throws -> (Double, String?) {
        var totalCents = 0.0
        var currency: String?
        var startingAfter: String?
        for _ in 0..<10 {
            let page = try await fetchPage(startingAfter: startingAfter)
            for sub in page.data {
                for item in sub.items.data {
                    guard let recurring = item.price.recurring else { continue }
                    currency = currency ?? item.price.currency
                    totalCents += Self.monthlyCents(unitAmount: item.price.unit_amount ?? 0,
                                                    quantity: item.quantity ?? 1,
                                                    interval: recurring.interval,
                                                    intervalCount: recurring.interval_count ?? 1)
                }
            }
            guard page.has_more, let last = page.data.last else { break }
            startingAfter = last.id
        }
        return (totalCents / 100, currency)
    }

    private func fetchPage(startingAfter: String?) async throws -> SubscriptionsPage {
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
            case 401: throw StripeError(message: String(localized: "Clé API invalide"))
            case 403: throw StripeError(message: String(localized: "Clé sans accès aux abonnements — crée une clé restreinte avec « Subscriptions : lecture »"))
            default:  throw StripeError(message: "HTTP \(http.statusCode)")
            }
        }
        return try JSONDecoder().decode(SubscriptionsPage.self, from: data)
    }

    // MARK: - Normalisation / format (pur, testable)

    /// Montant mensuel en cents d'une ligne d'abonnement.
    nonisolated static func monthlyCents(unitAmount: Int, quantity: Int, interval: String, intervalCount: Int) -> Double {
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

    nonisolated static func format(_ amount: Double) -> String {
        amount >= 100 ? String(Int(amount.rounded())) : String(format: "%.2f", amount)
    }

    nonisolated static func symbol(for currency: String) -> String {
        switch currency.lowercased() {
        case "eur": return "€"
        case "usd": return "$"
        case "gbp": return "£"
        default:    return " " + currency.uppercased()
        }
    }
}
