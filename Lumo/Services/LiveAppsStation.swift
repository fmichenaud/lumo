import Foundation
import Observation

/// Moteur des "apps live" : des sources de données (CPU, RAM, crypto) qu'on branche sur l'afficheur
/// et que Lumo maintient à jour automatiquement en arrière-plan (tant que le process vit, via la menu-bar).
/// Pas de `save` (flash) car mises à jour fréquentes : l'app est gardée vivante par re-push.
@MainActor
@Observable
final class LiveAppsStation {
    var cpuOn: Bool
    var ramOn: Bool
    var cryptoOn: Bool
    var coinID: String
    var currency: String

    var cpuValue = 0
    var ramValue = 0
    var cryptoPrice: Double?

    private weak var store: DeviceStore?
    private var ticker: Task<Void, Never>?
    private var tickCount = 0
    private let defaults = UserDefaults.standard
    private let tick: UInt64 = 5_000_000_000   // 5 s
    private let cryptoEveryTicks = 12          // ≈ 60 s

    init() {
        cpuOn = defaults.bool(forKey: "lumo.live.cpu")
        ramOn = defaults.bool(forKey: "lumo.live.ram")
        cryptoOn = defaults.bool(forKey: "lumo.live.crypto")
        coinID = defaults.string(forKey: "lumo.live.coin") ?? "bitcoin"
        currency = defaults.string(forKey: "lumo.live.cur") ?? "eur"
    }

    var currencySymbol: String { currency == "eur" ? "€" : "$" }
    var coinSymbol: String { DataService.coins.first { $0.id == coinID }?.symbol ?? "?" }
    private var anyOn: Bool { cpuOn || ramOn || cryptoOn }

    func attach(_ store: DeviceStore) {
        self.store = store
        if anyOn { startTicker() }
    }

    // MARK: - Activation des sources

    func setCPU(_ on: Bool) {
        cpuOn = on; defaults.set(on, forKey: "lumo.live.cpu")
        if on { Task { await refreshCPU() } } else { Task { await remove("cpu") } }
        ensureTicker()
    }

    func setRAM(_ on: Bool) {
        ramOn = on; defaults.set(on, forKey: "lumo.live.ram")
        if on { Task { await refreshRAM() } } else { Task { await remove("ram") } }
        ensureTicker()
    }

    func setCrypto(_ on: Bool) {
        cryptoOn = on; defaults.set(on, forKey: "lumo.live.crypto")
        if on { Task { await refreshCrypto() } } else { Task { await remove("crypto") } }
        ensureTicker()
    }

    func setCoin(_ id: String) {
        coinID = id; defaults.set(id, forKey: "lumo.live.coin")
        if cryptoOn { Task { await refreshCrypto() } }
    }

    func setCurrency(_ c: String) {
        currency = c; defaults.set(c, forKey: "lumo.live.cur")
        if cryptoOn { Task { await refreshCrypto() } }
    }

    // MARK: - Boucle

    private func ensureTicker() {
        if anyOn { startTicker() } else { ticker?.cancel(); ticker = nil }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runTick()
                try? await Task.sleep(nanoseconds: self?.tick ?? 5_000_000_000)
            }
        }
    }

    private func runTick() async {
        tickCount += 1
        if cpuOn { await refreshCPU() }
        if ramOn { await refreshRAM() }
        if cryptoOn && tickCount % cryptoEveryTicks == 1 { await refreshCrypto() }
    }

    // MARK: - Rafraîchissements

    private func refreshCPU() async {
        cpuValue = SystemStats.cpuUsagePercent()
        await push("cpu", ["text": "CPU \(cpuValue)%", "color": "#FFC400",
                           "progress": cpuValue, "progressC": "#FFC400"])
    }

    private func refreshRAM() async {
        ramValue = SystemStats.memoryUsagePercent()
        await push("ram", ["text": "RAM \(ramValue)%", "color": "#3DD68C",
                           "progress": ramValue, "progressC": "#3DD68C"])
    }

    private func refreshCrypto() async {
        guard let price = try? await DataService.cryptoPrice(id: coinID, currency: currency) else { return }
        cryptoPrice = price
        await push("crypto", ["text": "\(coinSymbol) \(format(price))\(currencySymbol)", "color": "#FFC400"])
    }

    // MARK: - Device

    private func push(_ name: String, _ json: sending [String: Any]) async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host).upsertCustomAppRaw(name: name, json: json)
    }

    private func remove(_ name: String) async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host).deleteCustomApp(name: name)
    }

    private func format(_ p: Double) -> String {
        p >= 100 ? String(Int(p.rounded())) : String(format: "%.2f", p)
    }
}
