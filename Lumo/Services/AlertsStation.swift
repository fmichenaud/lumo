import Foundation
import Combine

/// Moteur des règles d'alerte : évalue les métriques surveillées à intervalle régulier
/// et déclenche notification / LED au franchissement d'un seuil (une seule fois par
/// franchissement — la règle se réarme quand la valeur repasse du bon côté).
@MainActor
final class AlertsStation: ObservableObject {
    @Published var rules: [AlertRule] = []
    @Published var lastValues: [UUID: Double] = [:]
    @Published private(set) var active: Set<UUID> = []

    private weak var store: DeviceStore?
    private weak var connectorsStation: ConnectorsStation?
    private var ticker: Task<Void, Never>?
    private let storageKey = "lumo.alertrules.v1"
    private let lastFiredKey = "lumo.alertrules.lastfired.v1"
    private let tick: UInt64 = 10_000_000_000   // 10 s

    /// Règles planifiées déjà déclenchées : id → jour (« 2026-07-15 »), persisté
    /// pour ne pas re-déclencher après un redémarrage de l'app le même jour.
    private var lastFired: [UUID: String] = [:]
    /// Minutes depuis minuit au tick précédent (nil au premier tick).
    private var lastTickMinutes: Int?

    init() { load() }

    func attach(_ store: DeviceStore, connectors: ConnectorsStation) {
        self.store = store
        self.connectorsStation = connectors
        ensureTicker()
    }

    // MARK: - CRUD

    func add(_ rule: AlertRule) { rules.append(rule); persist(); ensureTicker() }

    func update(_ rule: AlertRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i] = rule
        active.remove(rule.id)               // condition modifiée → on réarme
        lastFired.removeValue(forKey: rule.id)   // horaire modifié → peut retirer aujourd'hui
        persist(); persistLastFired(); ensureTicker()
    }

    func remove(_ rule: AlertRule) {
        rules.removeAll { $0.id == rule.id }
        active.remove(rule.id)
        lastFired.removeValue(forKey: rule.id)
        persist(); persistLastFired(); ensureTicker()
    }

    func setEnabled(_ rule: AlertRule, _ on: Bool) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i].enabled = on
        if !on { active.remove(rule.id) }
        persist(); ensureTicker()
    }

    /// Déclenche la règle immédiatement (bouton « Tester »), avec la dernière valeur connue.
    func test(_ rule: AlertRule) async {
        guard let device = store?.selectedDevice else { return }
        let value = lastValues[rule.id] ?? rule.threshold
        await fire(rule, value: value, host: device.host)
    }

    // MARK: - Boucle

    private func ensureTicker() {
        if rules.contains(where: { $0.enabled }) { startTicker() }
        else { ticker?.cancel(); ticker = nil }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runTick()
                try? await Task.sleep(nanoseconds: self?.tick ?? 10_000_000_000)
            }
        }
    }

    private func runTick() async {
        guard let device = store?.selectedDevice else { return }
        await runScheduleTick(host: device.host, now: Date())
        // Un seul appel /api/stats par tick, partagé par toutes les règles device.
        var deviceStats: AwtrixStats?
        if rules.contains(where: { $0.enabled && $0.trigger == .threshold && $0.metric.needsDeviceStats }) {
            deviceStats = try? await AwtrixClient(host: device.host).fetchStats()
        }
        for rule in rules where rule.enabled && rule.trigger == .threshold {
            guard let value = currentValue(for: rule, stats: deviceStats) else { continue }
            lastValues[rule.id] = value
            let triggered = rule.isTriggered(value: value)
            if triggered && !active.contains(rule.id) {
                active.insert(rule.id)
                await fire(rule, value: value, host: device.host)
            } else if !triggered && active.contains(rule.id) {
                active.remove(rule.id)
                if rule.indicator > 0 {
                    try? await AwtrixClient(host: device.host).clearIndicator(rule.indicator)
                }
            }
        }
    }

    /// Évalue les règles planifiées : déclenche celles dont l'horaire vient d'être franchi.
    private func runScheduleTick(host: String, now: Date) async {
        let comps = Calendar.current.dateComponents([.hour, .minute, .weekday], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let weekday = comps.weekday ?? 1
        let today = Self.dayKey(now)
        defer { lastTickMinutes = nowMinutes }

        for rule in rules where rule.enabled && rule.trigger == .schedule {
            let shouldFire = Self.scheduleShouldFire(
                nowMinutes: nowMinutes,
                lastTickMinutes: lastTickMinutes,
                scheduleMinutes: rule.scheduleMinutes,
                weekday: weekday,
                allowedDays: rule.scheduleDays,
                alreadyFiredToday: lastFired[rule.id] == today
            )
            guard shouldFire else { continue }
            lastFired[rule.id] = today
            persistLastFired()
            await fire(rule, value: 0, host: host)
        }
    }

    /// Doit-on déclencher une règle planifiée ? Fonction pure, testable.
    /// - `nowMinutes` / `lastTickMinutes` : minutes depuis minuit (lastTick nil au premier tick).
    /// - `weekday` : jour courant façon Calendar (1=dimanche…7=samedi).
    /// - `allowedDays` : jours autorisés (vide = tous les jours).
    /// Règles : on tire quand l'horaire est franchi entre deux ticks. Au premier tick,
    /// on ne rattrape pas un horaire déjà passé (on ne tire que pile à la minute prévue).
    /// Après minuit, les horaires de la veille manqués ne sont pas rattrapés.
    nonisolated static func scheduleShouldFire(
        nowMinutes: Int,
        lastTickMinutes: Int?,
        scheduleMinutes: Int,
        weekday: Int,
        allowedDays: Set<Int>,
        alreadyFiredToday: Bool
    ) -> Bool {
        guard !alreadyFiredToday else { return false }
        guard allowedDays.isEmpty || allowedDays.contains(weekday) else { return false }
        guard let last = lastTickMinutes else { return nowMinutes == scheduleMinutes }
        if nowMinutes >= last {
            // Tick ordinaire : l'horaire est dans l'intervalle ]last, now].
            return last < scheduleMinutes && scheduleMinutes <= nowMinutes
        }
        // Minuit franchi entre les deux ticks : seul l'intervalle [00:00, now] compte
        // (le jour a changé, alreadyFiredToday et weekday se réfèrent à aujourd'hui).
        return scheduleMinutes <= nowMinutes
    }

    /// « 2026-07-15 » — clé du jour pour lastFired.
    nonisolated static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func currentValue(for rule: AlertRule, stats: AwtrixStats?) -> Double? {
        switch rule.metric {
        case .macCPU:         return Double(SystemStats.cpuUsagePercent())
        case .macRAM:         return Double(SystemStats.memoryUsagePercent())
        case .deviceBattery:  return stats?.bat.map(Double.init)
        case .deviceTemp:     return stats?.temp
        case .deviceHumidity: return stats?.hum
        case .claudeSession:  return connectorsStation?.specialMetrics["claude.session"]
        case .claudeWeekly:   return connectorsStation?.specialMetrics["claude.weekly"]
        case .stripeMRR:      return connectorsStation?.specialMetrics["stripe.mrr"]
        case .stripeTotal:    return connectorsStation?.specialMetrics["stripe.total"]
        case .connector:
            guard let id = rule.connectorID,
                  let text = connectorsStation?.lastValue[id] else { return nil }
            return AlertRule.numericValue(from: text)
        }
    }

    private func fire(_ rule: AlertRule, value: Double, host: String) async {
        let client = AwtrixClient(host: host)
        // Règle planifiée avec une app cible : on bascule la rotation sur cette app
        // au lieu d'envoyer une notification (la LED témoin reste gérée plus bas).
        let targetApp = rule.switchToApp.trimmingCharacters(in: .whitespaces)
        if rule.trigger == .schedule && !targetApp.isEmpty {
            try? await client.switchApp(name: targetApp)
            if rule.indicator > 0 {
                try? await client.setIndicator(rule.indicator, rgb: Self.rgb(fromHex: rule.colorHex))
            }
            return
        }
        var payload = PushPayload()
        payload.text = rule.renderedMessage(value: value)
        payload.color = rule.colorHex
        let icon = rule.icon.trimmingCharacters(in: .whitespaces)
        if !icon.isEmpty { payload.icon = icon }
        if !rule.sound.isEmpty { payload.sound = rule.sound }
        payload.wakeup = true
        try? await client.notify(payload)
        if rule.indicator > 0 {
            try? await client.setIndicator(rule.indicator, rgb: Self.rgb(fromHex: rule.colorHex))
        }
    }

    /// "#RRGGBB" → [r, g, b].
    nonisolated static func rgb(fromHex hex: String) -> [Int] {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        return [Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF)]
    }

    // MARK: - Persistance

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([AlertRule].self, from: data) {
            rules = saved
        }
        if let data = UserDefaults.standard.data(forKey: lastFiredKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            lastFired = saved.reduce(into: [:]) { dict, entry in
                if let id = UUID(uuidString: entry.key) { dict[id] = entry.value }
            }
        }
    }

    private func persistLastFired() {
        let raw = lastFired.reduce(into: [String: String]()) { $0[$1.key.uuidString] = $1.value }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: lastFiredKey)
        }
    }
}
