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
    private weak var claudeStation: ClaudeUsageStation?
    private weak var stripeStation: StripeStation?
    private var ticker: Task<Void, Never>?
    private let storageKey = "lumo.alertrules.v1"
    private let tick: UInt64 = 10_000_000_000   // 10 s

    init() { load() }

    func attach(_ store: DeviceStore, connectors: ConnectorsStation,
                claude: ClaudeUsageStation, stripe: StripeStation) {
        self.store = store
        self.connectorsStation = connectors
        self.claudeStation = claude
        self.stripeStation = stripe
        ensureTicker()
    }

    // MARK: - CRUD

    func add(_ rule: AlertRule) { rules.append(rule); persist(); ensureTicker() }

    func update(_ rule: AlertRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i] = rule
        active.remove(rule.id)   // condition modifiée → on réarme
        persist(); ensureTicker()
    }

    func remove(_ rule: AlertRule) {
        rules.removeAll { $0.id == rule.id }
        active.remove(rule.id)
        persist(); ensureTicker()
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
        // Un seul appel /api/stats par tick, partagé par toutes les règles device.
        var deviceStats: AwtrixStats?
        if rules.contains(where: { $0.enabled && $0.metric.needsDeviceStats }) {
            deviceStats = try? await AwtrixClient(host: device.host).fetchStats()
        }
        for rule in rules where rule.enabled {
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

    private func currentValue(for rule: AlertRule, stats: AwtrixStats?) -> Double? {
        switch rule.metric {
        case .macCPU:         return Double(SystemStats.cpuUsagePercent())
        case .macRAM:         return Double(SystemStats.memoryUsagePercent())
        case .deviceBattery:  return stats?.bat.map(Double.init)
        case .deviceTemp:     return stats?.temp
        case .deviceHumidity: return stats?.hum
        case .claudeSession:  return claudeStation?.sessionPercent
        case .claudeWeekly:   return claudeStation?.weeklyPercent
        case .stripeMRR:      return stripeStation?.mrr
        case .connector:
            guard let id = rule.connectorID,
                  let text = connectorsStation?.lastValue[id] else { return nil }
            return AlertRule.numericValue(from: text)
        }
    }

    private func fire(_ rule: AlertRule, value: Double, host: String) async {
        let client = AwtrixClient(host: host)
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
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([AlertRule].self, from: data) else { return }
        rules = saved
    }
}
