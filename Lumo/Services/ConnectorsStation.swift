import Foundation
import Combine

/// Moteur des connecteurs : stocke la liste, rafraîchit chaque connecteur actif sur son intervalle,
/// pousse le résultat sur l'afficheur, et permet de tester un connecteur à la volée.
@MainActor
final class ConnectorsStation: ObservableObject {
    @Published var connectors: [Connector] = []
    @Published var lastValue: [UUID: String] = [:]
    @Published var lastError: [UUID: String] = [:]
    /// Métriques numériques des sources spéciales, pour les règles d'alerte
    /// (clés : "claude.session", "claude.weekly", "stripe.mrr").
    @Published var specialMetrics: [String: Double] = [:]

    private weak var store: DeviceStore?
    private var ticker: Task<Void, Never>?
    private var lastRun: [UUID: Date] = [:]
    private var uploadedIcons: Set<String> = []
    private let storageKey = "lumo.connectors.v3"

    init() { load() }

    func attach(_ store: DeviceStore) {
        self.store = store
        if connectors.contains(where: { $0.enabled }) { startTicker() }
    }

    // MARK: - CRUD

    func add(_ c: Connector) { connectors.append(c); persist() }

    func update(_ c: Connector) {
        guard let i = connectors.firstIndex(where: { $0.id == c.id }) else { return }
        connectors[i] = c; persist()
        if c.enabled { Task { await refresh(c) } }
    }

    func remove(_ c: Connector) {
        connectors.removeAll { $0.id == c.id }
        persist()
        Task { await removeFromDevice(c) }
    }

    func setEnabled(_ c: Connector, _ on: Bool) {
        guard let i = connectors.firstIndex(where: { $0.id == c.id }) else { return }
        connectors[i].enabled = on
        persist()
        if on { Task { await refresh(connectors[i]) }; startTicker() }
        else { Task { await removeFromDevice(c) }; stopTickerIfIdle() }
    }

    // MARK: - Boucle

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func stopTickerIfIdle() {
        if !connectors.contains(where: { $0.enabled }) { ticker?.cancel(); ticker = nil }
    }

    private func tick() async {
        let now = Date()
        for c in connectors where c.enabled {
            let due = now.timeIntervalSince(lastRun[c.id] ?? .distantPast) >= Double(max(10, c.intervalSeconds))
            if due { await refresh(c) }
        }
    }

    // MARK: - Récupération / envoi

    /// Récupère la valeur d'un connecteur (sans pousser) — utilisé par le bouton Tester.
    /// Renvoie (valeur, erreur) : l'un des deux est nil.
    func fetchValue(_ c: Connector) async -> (value: String?, error: String?) {
        // Sources spéciales : services hors du moule URL + chemin JSON.
        switch c.special {
        case .claudeQuota:
            do {
                let usage = try await ClaudeQuotaSource.fetch()
                if let s = usage.session { specialMetrics["claude.session"] = s }
                if let w = usage.weekly { specialMetrics["claude.weekly"] = w }
                return (usage.value, nil)
            } catch let error as ClaudeQuotaSource.SourceError {
                return (nil, error.message)
            } catch {
                return (nil, String(localized: "Échec réseau"))
            }
        case .stripeMRR:
            do {
                let result = try await StripeMRRSource.fetch(apiKey: c.auth.bearerToken)
                specialMetrics["stripe.mrr"] = result.mrr
                return (result.value, nil)
            } catch let error as StripeMRRSource.SourceError {
                return (nil, error.message)
            } catch {
                return (nil, String(localized: "Échec réseau"))
            }
        case nil:
            break
        }
        guard let url = URL(string: c.url) else { return (nil, "URL invalide") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        for (k, v) in c.requestHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let h = resp as? HTTPURLResponse {
                if h.statusCode == 204 || data.isEmpty { return (nil, "En attente de données…") }
                if !(200..<300).contains(h.statusCode) { return (nil, "HTTP \(h.statusCode)") }
            }
            if data.isEmpty { return (nil, "En attente de données…") }
            guard let value = JSONValue.extract(path: c.jsonPath, from: data) else {
                return (nil, "Donnée absente pour le moment")
            }
            return (value, nil)
        } catch {
            return (nil, "Échec réseau")
        }
    }

    /// Lance le flux OAuth 2.0 et renvoie le connecteur mis à jour avec le token (ou nil en cas d'échec).
    func authorize(_ c: Connector) async -> Connector? {
        guard let token = try? await OAuthService.shared.authorize(c.auth) else { return nil }
        var updated = c
        updated.auth.accessToken = token
        if connectors.contains(where: { $0.id == c.id }) { update(updated) }
        return updated
    }

    @discardableResult
    func test(_ c: Connector) async -> String? {
        let (value, error) = await fetchValue(c)
        if let value { lastValue[c.id] = value; lastError[c.id] = nil; return value }
        lastError[c.id] = error
        return nil
    }

    private func refresh(_ c: Connector) async {
        lastRun[c.id] = Date()
        let (value, error) = await fetchValue(c)
        if let value {
            lastValue[c.id] = value
            lastError[c.id] = nil
            await push(c, text: c.renderedText(value: value))
        } else if !c.fallbackText.isEmpty {
            // Pas de donnée (ex. Spotify en pause) → on affiche le texte de repli au lieu de rester figé.
            lastValue[c.id] = nil
            lastError[c.id] = error
            await push(c, text: c.fallbackText)
        } else {
            lastError[c.id] = error
        }
    }

    private func push(_ c: Connector, text: String) async {
        guard let device = store?.selectedDevice else { return }
        await ensureIcon(c, host: device.host)
        // Quota Claude : la couleur suit le niveau (vert → orange → rouge) au lieu d'être fixe.
        var color = c.colorHex
        if c.special == .claudeQuota {
            let worst = max(specialMetrics["claude.session"] ?? 0, specialMetrics["claude.weekly"] ?? 0)
            color = ClaudeQuotaSource.color(forPercent: worst)
        }
        // repeat: 1 → l'app reste affichée jusqu'à ce que le texte ait défilé une fois en entier.
        var json: [String: Any] = ["text": text, "color": color, "repeat": 1]
        let icon = c.icon.trimmingCharacters(in: .whitespaces)
        if !icon.isEmpty { json["icon"] = icon }
        try? await AwtrixClient(host: device.host).upsertCustomAppRaw(name: c.appName, json: json)
    }

    /// Téléverse l'icône par défaut (ID LaMetric numérique) une seule fois si elle n'est pas déjà sur le device.
    private func ensureIcon(_ c: Connector, host: String) async {
        let icon = c.icon.trimmingCharacters(in: .whitespaces)
        guard !icon.isEmpty, icon.allSatisfy(\.isNumber), !uploadedIcons.contains(icon) else { return }
        if let data = try? await LaMetricService.fetchIcon(id: icon),
           let gif = IconConverter.awtrixGIF(from: data) {
            try? await AwtrixClient(host: host).uploadIcon(id: icon, data: gif, ext: "gif")
            uploadedIcons.insert(icon)
        }
    }

    private func removeFromDevice(_ c: Connector) async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host).deleteCustomApp(name: c.appName)
    }

    // MARK: - Persistance

    private func persist() {
        if let data = try? JSONEncoder().encode(connectors) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Connector].self, from: data) else { return }
        connectors = saved
    }
}
