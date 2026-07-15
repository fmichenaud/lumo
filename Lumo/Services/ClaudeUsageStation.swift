import Foundation
import Combine
import Security

/// Intégration Claude Code : lit le token OAuth de Claude Code dans le Trousseau
/// (service "Claude Code-credentials", entretenu par Claude Code lui-même) et interroge
/// l'endpoint d'usage pour afficher les quotas — session 5 h et semaine — sur l'afficheur.
@MainActor
final class ClaudeUsageStation: ObservableObject {

    /// Ce qu'on affiche sur la matrice.
    enum Display: String, CaseIterable, Identifiable {
        case both, session, weekly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .both:    return String(localized: "Session + semaine")
            case .session: return String(localized: "Session (5 h)")
            case .weekly:  return String(localized: "Semaine")
            }
        }
    }

    @Published private(set) var enabled: Bool
    @Published private(set) var display: Display
    @Published private(set) var sessionPercent: Double?
    @Published private(set) var weeklyPercent: Double?
    @Published private(set) var lastError: String?

    private weak var store: DeviceStore?
    private var ticker: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    init() {
        enabled = defaults.bool(forKey: "lumo.claude.on")
        display = Display(rawValue: defaults.string(forKey: "lumo.claude.display") ?? "") ?? .both
    }

    func attach(_ store: DeviceStore) {
        self.store = store
        if enabled { startTicker() }
    }

    var summaryText: String? {
        guard sessionPercent != nil || weeklyPercent != nil else { return nil }
        let s = sessionPercent.map { "\(Int($0))%" } ?? "—"
        let w = weeklyPercent.map { "\(Int($0))%" } ?? "—"
        return String(localized: "Session \(s) · Semaine \(w)")
    }

    // MARK: - Réglages

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: "lumo.claude.on")
        if on {
            startTicker()
            Task { await refresh() }
        } else {
            ticker?.cancel(); ticker = nil
            Task { await remove() }
        }
    }

    func setDisplay(_ d: Display) {
        display = d
        defaults.set(d.rawValue, forKey: "lumo.claude.display")
        if enabled { Task { await push() } }
    }

    // MARK: - Boucle

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 60_000_000_000)   // 60 s
            }
        }
    }

    func refresh() async {
        do {
            let usage = try await Self.fetchUsage()
            sessionPercent = usage.session
            weeklyPercent = usage.weekly
            lastError = nil
            if enabled { await push() }
        } catch let error as UsageError {
            lastError = error.message
        } catch {
            lastError = String(localized: "Échec réseau")
        }
    }

    private func push() async {
        guard let device = store?.selectedDevice else { return }
        let text = Self.text(session: sessionPercent, weekly: weeklyPercent, display: display)
        guard !text.isEmpty else { return }
        let worst = max(sessionPercent ?? 0, weeklyPercent ?? 0)
        let json: [String: Any] = ["text": text, "color": Self.color(forPercent: worst), "repeat": 1]
        try? await AwtrixClient(host: device.host).upsertCustomAppRaw(name: "claude", json: json)
    }

    private func remove() async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host).deleteCustomApp(name: "claude")
    }

    // MARK: - Texte / couleur (pur, testable)

    nonisolated static func text(session: Double?, weekly: Double?, display: Display) -> String {
        let s = session.map { "\(Int($0))%" }
        let w = weekly.map { "\(Int($0))%" }
        switch display {
        case .session: return s.map { "CC \($0)" } ?? ""
        case .weekly:  return w.map { "CC 7j \($0)" } ?? ""
        case .both:
            guard s != nil || w != nil else { return "" }
            return "CC \(s ?? "—") · 7j \(w ?? "—")"
        }
    }

    /// Vert tant qu'on est large, orange quand ça chauffe, rouge près de la limite.
    nonisolated static func color(forPercent p: Double) -> String {
        if p >= 90 { return "#FF5555" }
        if p >= 70 { return "#FFC400" }
        return "#3DD68C"
    }

    // MARK: - Réseau / Trousseau

    struct UsageError: Error { let message: String }

    private struct UsageResponse: Decodable {
        struct Bucket: Decodable { let utilization: Double? }
        let five_hour: Bucket?
        let seven_day: Bucket?
    }

    nonisolated static func fetchUsage() async throws -> (session: Double?, weekly: Double?) {
        guard let token = keychainToken() else {
            throw UsageError(message: String(localized: "Token introuvable — ouvre Claude Code une fois, puis autorise Lumo dans le Trousseau."))
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 {
                throw UsageError(message: String(localized: "Token expiré — relance Claude Code pour le rafraîchir."))
            }
            throw UsageError(message: "HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        return (decoded.five_hour?.utilization, decoded.seven_day?.utilization)
    }

    /// Lit le token OAuth stocké par Claude Code (déclenche une autorisation Trousseau au 1er accès).
    nonisolated static func keychainToken() -> String? {
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
