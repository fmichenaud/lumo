import Foundation
import Combine

/// Minuteur / Pomodoro affiché sur la matrice : une app custom "timer" est mise à jour chaque
/// seconde (temps restant + barre de progression), et une notification sonore part à zéro.
/// Vit au niveau de l'app (comme les autres stations) pour continuer via la menu-bar.
@MainActor
final class PomodoroStation: ObservableObject {

    /// État du minuteur.
    enum TimerState: Equatable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    /// Durées rapides proposées dans l'UI (minutes).
    static let presets = [5, 15, 25, 45]

    @Published private(set) var state: TimerState = .idle
    @Published private(set) var remaining: TimeInterval = 0  // temps restant pour l'UI, mis à jour chaque seconde
    @Published private(set) var cycleCount = 0               // cycles de travail terminés (mode Pomodoro)
    @Published private(set) var onBreak = false              // phase "pause" du mode Pomodoro
    @Published private(set) var customMinutes: Int
    @Published private(set) var pomodoroMode: Bool
    @Published private(set) var endMessage: String

    private var totalDuration: TimeInterval = 1              // durée totale de la phase en cours (s)
    private weak var store: DeviceStore?
    private var ticker: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private static let appName = "timer"
    private static let workMinutes = 25
    private static let breakMinutes = 5
    /// Sonnerie de fin courte (~1,5 s), format RTTTL : nom:défauts:notes.
    static let endMelody = "lumo:d=16,o=6,b=180:c,e,g,8c7,8p,c,e,g,8c7"

    init() {
        let saved = defaults.integer(forKey: "lumo.timer.minutes")
        customMinutes = saved > 0 ? saved : 25
        pomodoroMode = defaults.bool(forKey: "lumo.timer.pomodoro")
        endMessage = defaults.string(forKey: "lumo.timer.message") ?? "Terminé !"
    }

    /// Relie le store des devices (appelé au lancement).
    func attach(_ store: DeviceStore) {
        self.store = store
    }

    // MARK: - État dérivé

    var isActive: Bool { state != .idle }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Sous-titre affiché dans le hub : « 12:34 restantes » / « En pause » / « Inactif ».
    var statusText: String {
        switch state {
        case .idle:
            return "Inactif"
        case .paused:
            return "En pause"
        case .running:
            let time = Self.timeText(Int(remaining.rounded()))
            return onBreak ? "Pause · \(time) restantes" : "\(time) restantes"
        }
    }

    // MARK: - Réglages (persistés)

    func setMinutes(_ minutes: Int) {
        customMinutes = max(1, min(180, minutes))
        defaults.set(customMinutes, forKey: "lumo.timer.minutes")
    }

    func setPomodoroMode(_ on: Bool) {
        pomodoroMode = on
        defaults.set(on, forKey: "lumo.timer.pomodoro")
    }

    func setEndMessage(_ text: String) {
        endMessage = text
        defaults.set(text, forKey: "lumo.timer.message")
    }

    // MARK: - Commandes

    /// Démarre le décompte (ou le premier cycle de travail en mode Pomodoro) et bascule
    /// l'affichage sur l'app "timer".
    func start() {
        onBreak = false
        cycleCount = 0
        startPhase(minutes: pomodoroMode ? Self.workMinutes : customMinutes)
    }

    /// Fige le décompte : l'app "timer" reste à l'écran avec le temps figé.
    func pause() {
        guard case .running(let end) = state else { return }
        let rem = max(0, end.timeIntervalSinceNow)
        stopTicker()
        state = .paused(remaining: rem)
        remaining = rem
        Task { await pushTimer(seconds: Int(rem.rounded())) }
    }

    /// Reprend là où le décompte s'était arrêté.
    func resume() {
        guard case .paused(let rem) = state else { return }
        state = .running(endDate: Date().addingTimeInterval(rem))
        startTicker()
    }

    /// Arrête tout et retire l'app "timer" de l'afficheur.
    func stop() {
        stopTicker()
        state = .idle
        remaining = 0
        onBreak = false
        cycleCount = 0
        Task { await removeFromDevice() }
    }

    // MARK: - Phases

    /// Lance une phase (travail ou pause) : pousse l'app tout de suite et bascule dessus.
    private func startPhase(minutes: Int) {
        let total = TimeInterval(max(1, minutes) * 60)
        totalDuration = total
        remaining = total
        state = .running(endDate: Date().addingTimeInterval(total))
        startTicker()
        Task {
            await pushTimer(seconds: Int(total))
            await switchToTimer()
        }
    }

    /// Fin de phase : notifie (texte + mélodie), puis enchaîne (Pomodoro) ou s'arrête.
    private func finish() async {
        if pomodoroMode {
            if onBreak {
                // Fin de la pause → nouveau cycle de travail.
                await notifyEnd(text: "Au travail !")
                onBreak = false
                startPhase(minutes: Self.workMinutes)
            } else {
                // Fin du travail → petite pause.
                cycleCount += 1
                await notifyEnd(text: endMessage.isEmpty ? "Pause !" : endMessage)
                onBreak = true
                startPhase(minutes: Self.breakMinutes)
            }
        } else {
            stopTicker()
            state = .idle
            remaining = 0
            await notifyEnd(text: endMessage.isEmpty ? "Terminé !" : endMessage)
            await removeFromDevice()
        }
    }

    // MARK: - Boucle

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() async {
        guard case .running(let end) = state else { return }
        let rem = end.timeIntervalSinceNow
        if rem <= 0 {
            remaining = 0
            await finish()
        } else {
            remaining = rem
            await pushTimer(seconds: Int(rem.rounded()))
        }
    }

    // MARK: - Device

    /// Pousse l'app "timer" : temps MM:SS, couleur selon le pourcentage restant, barre de progression.
    private func pushTimer(seconds: Int) async {
        guard let device = store?.selectedDevice else { return }
        let pct = Self.percentRemaining(remaining: TimeInterval(seconds), total: totalDuration)
        let color = Self.colorHex(forPercentRemaining: pct)
        try? await AwtrixClient(host: device.host).upsertCustomAppRaw(name: Self.appName, json: [
            "text": Self.timeText(seconds),
            "color": color,
            "progress": pct,
            "progressC": color
        ])
    }

    private func switchToTimer() async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host).switchApp(name: Self.appName)
    }

    private func notifyEnd(text: String) async {
        guard let device = store?.selectedDevice else { return }
        var payload = PushPayload()
        payload.text = text
        payload.color = "#3DD68C"
        payload.wakeup = true
        payload.hold = false
        payload.rtttl = Self.endMelody
        try? await AwtrixClient(host: device.host).notify(payload)
    }

    private func removeFromDevice() async {
        guard let device = store?.selectedDevice else { return }
        try? await AwtrixClient(host: device.host).deleteCustomApp(name: Self.appName)
    }

    // MARK: - Logique pure (testable)

    /// Formate un nombre de secondes en "MM:SS" (les minutes peuvent dépasser 59).
    nonisolated static func timeText(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Pourcentage restant (0–100) borné, sûre même si total ≤ 0.
    nonisolated static func percentRemaining(remaining: TimeInterval, total: TimeInterval) -> Int {
        guard total > 0 else { return 0 }
        return max(0, min(100, Int((remaining / total * 100).rounded())))
    }

    /// Vert, puis orange sous 20 % restants, rouge sous 10 %.
    nonisolated static func colorHex(forPercentRemaining percent: Int) -> String {
        if percent < 10 { return "#FF5555" }
        if percent < 20 { return "#FFC400" }
        return "#3DD68C"
    }
}
