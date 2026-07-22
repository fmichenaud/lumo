import Foundation
import Observation

/// Moteur des connecteurs : stocke la liste, rafraîchit chaque connecteur actif sur son intervalle,
/// pousse le résultat sur l'afficheur, et permet de tester un connecteur à la volée.
@MainActor
@Observable
final class ConnectorsStation {
    var connectors: [Connector] = []
    var lastValue: [UUID: String] = [:]
    var lastError: [UUID: String] = [:]
    /// Métriques numériques des sources spéciales, pour les règles d'alerte
    /// (clés : "claude.session", "claude.weekly", "stripe.mrr").
    var specialMetrics: [String: Double] = [:]
    /// Dernier relevé de quota Claude (pourcentages + heures de reset).
    var claudeQuota: ClaudeQuotaSource.Quota?

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

    /// Au plus 4 connecteurs interrogés de front : assez pour ne pas se bloquer les uns
    /// les autres, pas assez pour saturer le réseau ni l'afficheur.
    private static let maxParallelRefresh = 4

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                // Se réveiller à la prochaine échéance plutôt que toutes les 5 s :
                // avec des intervalles longs (30 min pour Stripe), inutile de tourner à vide.
                let delay = self?.delayUntilNextDue() ?? 5_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func stopTickerIfIdle() {
        if !connectors.contains(where: { $0.enabled }) { ticker?.cancel(); ticker = nil }
    }

    /// Attente avant le prochain connecteur dû, bornée à [1 s, 30 s] pour rester réactif
    /// aux changements de configuration.
    private func delayUntilNextDue(now: Date = Date()) -> UInt64 {
        let waits = connectors.filter(\.enabled).map { c -> Double in
            let interval = Double(max(10, c.intervalSeconds))
            return max(0, interval - now.timeIntervalSince(lastRun[c.id] ?? .distantPast))
        }
        let next = waits.min() ?? 5
        return UInt64(min(30, max(1, next)) * 1_000_000_000)
    }

    /// Rafraîchit les connecteurs échus en parallèle : un service lent (Stripe pagine,
    /// une API peut timeouter à 8 s) ne doit pas retarder tous les autres.
    private func tick() async {
        let now = Date()
        let due = connectors.filter { c in
            c.enabled && now.timeIntervalSince(lastRun[c.id] ?? .distantPast) >= Double(max(10, c.intervalSeconds))
        }
        guard !due.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = due.makeIterator()
            for _ in 0..<min(Self.maxParallelRefresh, due.count) {
                guard let c = iterator.next() else { break }
                group.addTask { await self.refresh(c) }
            }
            while await group.next() != nil {
                guard let c = iterator.next() else { continue }
                group.addTask { await self.refresh(c) }
            }
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
                claudeQuota = usage.quota
                if let s = usage.quota.session { specialMetrics["claude.session"] = s }
                if let w = usage.quota.weekly { specialMetrics["claude.weekly"] = w }
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
        case .stripeTotal:
            do {
                let result = try await StripeTotalSource.fetch(apiKey: c.auth.bearerToken)
                specialMetrics["stripe.total"] = result.total
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

    /// Texte final envoyé à l'afficheur, jetons de la source compris.
    func renderedText(_ c: Connector, value: String) -> String {
        c.renderedText(value: value, tokens: tokens(for: c))
    }

    /// Jetons de format disponibles pour ce connecteur (vide hors sources spéciales).
    private func tokens(for c: Connector) -> [String: String] {
        guard c.special == .claudeQuota, let quota = claudeQuota else { return [:] }
        return ClaudeQuotaSource.tokens(quota)
    }

    private func refresh(_ c: Connector) async {
        lastRun[c.id] = Date()
        let (value, error) = await fetchValue(c)
        if let value {
            lastValue[c.id] = value
            lastError[c.id] = nil
            await push(c, text: renderedText(c, value: value))
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
        // Quota Claude en mode auto : la couleur suit le niveau (vert → orange → rouge).
        // Sinon on respecte la couleur choisie dans l'éditeur.
        var color = c.colorHex
        if c.usesLevelColor, c.special == .claudeQuota {
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
    /// La mémoire est indexée par afficheur : changer de device re-téléverse ce qu'il lui manque.
    private func ensureIcon(_ c: Connector, host: String) async {
        let icon = c.icon.trimmingCharacters(in: .whitespaces)
        let key = "\(host)#\(icon)"
        guard !icon.isEmpty, icon.allSatisfy(\.isNumber), !uploadedIcons.contains(key) else { return }
        if let data = try? await LaMetricService.fetchIcon(id: icon),
           let gif = IconConverter.awtrixGIF(from: data) {
            try? await AwtrixClient(host: host).uploadIcon(id: icon, data: gif, ext: "gif")
            uploadedIcons.insert(key)
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
