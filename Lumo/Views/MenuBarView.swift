import SwiftUI

/// Contenu de la menu-bar : aperçu rapide et actions sans ouvrir la fenêtre.
struct MenuBarView: View {
    @Environment(DeviceStore.self) var store
    @Environment(WeatherStation.self) var weatherStation
    @Environment(ConnectorsStation.self) var connectors
    @Environment(PomodoroStation.self) var pomodoro
    @Environment(\.openWindow) private var openWindow

    @State private var sending = false
    /// État local optimiste de l'écran (synchronisé depuis /api/settings à l'apparition).
    @State private var screenOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            weatherBlock
            quotasBlock
            Divider()
            timerBlock
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 290)
        .task(id: store.selectedDevice?.id) { await refreshPower() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.accentGradient)
                .frame(width: 24, height: 24)
                .overlay(Image(systemName: "rays").font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.8)))
            VStack(alignment: .leading, spacing: 1) {
                Text(store.selectedDevice?.name ?? "Aucun afficheur")
                    .font(.callout.weight(.semibold))
                if let host = store.selectedDevice?.host {
                    Text(host).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var weatherBlock: some View {
        if let weather = weatherStation.weather {
            HStack(spacing: 12) {
                if let device = store.selectedDevice {
                    IconThumbnail(host: device.host, iconID: weather.condition.iconID)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(weatherStation.locationLabel).font(.caption).lineLimit(1)
                    Text(weather.condition.label).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(weather.tempText).font(.title3.weight(.semibold).monospacedDigit())
            }
        } else {
            Text("Météo non configurée").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Quotas & business

    @ViewBuilder private var quotasBlock: some View {
        let session = connectors.specialMetrics["claude.session"]
        let weekly = connectors.specialMetrics["claude.weekly"]
        let showClaude = connectors.connectors.contains { $0.special == .claudeQuota }
            && (session != nil || weekly != nil)
        let mrr = stripeValue(special: .stripeMRR, metricKey: "stripe.mrr")
        let total = stripeValue(special: .stripeTotal, metricKey: "stripe.total")

        if showClaude || mrr != nil || total != nil {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Quotas & business")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if showClaude {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: ClaudeQuotaSource.color(forPercent: max(session ?? 0, weekly ?? 0))))
                            .frame(width: 7, height: 7)
                        Text(Self.claudeLine(session: session, weekly: weekly))
                            .font(.caption.monospacedDigit())
                            .lineLimit(1)
                    }
                    if let reset = Self.claudeResetLine(connectors.claudeQuota) {
                        Text(reset)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.leading, 13)
                    }
                }
                if mrr != nil || total != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "creditcard.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 7)
                        Text(Self.stripeLine(mrr: mrr, total: total))
                            .font(.caption.monospacedDigit())
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// Valeur Stripe à afficher : le texte déjà formaté du connecteur (avec devise),
    /// sinon le montant brut de la métrique.
    private func stripeValue(special: Connector.SpecialSource, metricKey: String) -> String? {
        guard let metric = connectors.specialMetrics[metricKey] else { return nil }
        if let c = connectors.connectors.first(where: { $0.special == special }),
           let value = connectors.lastValue[c.id] {
            return value
        }
        return StripeMRRSource.format(metric)
    }

    // MARK: - Minuteur

    private var timerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(pomodoro.onBreak ? "Minuteur · pause" : "Minuteur", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if pomodoro.isActive {
                    Text(PomodoroStation.timeText(Int(pomodoro.remaining.rounded())))
                        .font(.callout.weight(.semibold).monospacedDigit())
                } else {
                    Text("Inactif").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                switch pomodoro.state {
                case .idle:
                    timerButton("Démarrer \(startMinutes) min", icon: "play.fill") { pomodoro.start() }
                case .running:
                    timerButton("Pause", icon: "pause.fill") { pomodoro.pause() }
                    timerButton("Stop", icon: "stop.fill", tint: .red) { pomodoro.stop() }
                case .paused:
                    timerButton("Reprendre", icon: "play.fill") { pomodoro.resume() }
                    timerButton("Stop", icon: "stop.fill", tint: .red) { pomodoro.stop() }
                }
                Spacer()
            }
        }
    }

    /// Minutes lancées par le bouton Démarrer (25 en mode Pomodoro, sinon la durée choisie).
    private var startMinutes: Int {
        pomodoro.pomodoroMode ? 25 : pomodoro.customMinutes
    }

    private func timerButton(_ title: LocalizedStringKey, icon: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint ?? .primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            if store.selectedDevice != nil {
                Toggle(isOn: Binding(
                    get: { screenOn },
                    set: { setPower($0) }
                )) {
                    Label("Écran allumé", systemImage: "display")
                }
            }

            if weatherStation.weather != nil && store.selectedDevice != nil {
                Button {
                    sending = true
                    Task { await weatherStation.push(switchTo: true); sending = false }
                } label: {
                    HStack {
                        Label("Envoyer la météo", systemImage: "paperplane.fill")
                        Spacer()
                        if sending { ProgressView().controlSize(.small) }
                    }
                    .frame(maxWidth: .infinity)
                }

                Toggle(isOn: Binding(
                    get: { weatherStation.autoEnabled },
                    set: { weatherStation.setAuto($0) }
                )) {
                    Label("Mise à jour auto (15 min)", systemImage: "clock.arrow.2.circlepath")
                }
            }

            Divider().padding(.vertical, 2)

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Ouvrir Lumo", systemImage: "macwindow").frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quitter", systemImage: "power").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Écran on/off

    private func setPower(_ on: Bool) {
        screenOn = on
        guard let device = store.selectedDevice else { return }
        Task { try? await AwtrixClient(host: device.host).setPower(on) }
    }

    /// Lit l'état réel de la matrice (clé MATP de /api/settings, absente du modèle typé).
    private func refreshPower() async {
        guard let host = store.selectedDevice?.host,
              let url = URL(string: "http://\(host)/api/settings") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let matp = obj["MATP"] as? Bool else { return }
        screenOn = matp
    }

    // MARK: - Formatage pur (testé dans MenuBarFormatterTests)

    /// « Claude : session 59 % · semaine 13 % » — n'affiche que les métriques disponibles.
    nonisolated static func claudeLine(session: Double?, weekly: Double?) -> String {
        var parts: [String] = []
        if let s = session { parts.append("session \(Int(s.rounded())) %") }
        if let w = weekly { parts.append("semaine \(Int(w.rounded())) %") }
        return "Claude : " + parts.joined(separator: " · ")
    }

    /// « Reset : session dans 2h19 · semaine dans 1j 4h » — nil si aucune heure de reset connue.
    nonisolated static func claudeResetLine(_ quota: ClaudeQuotaSource.Quota?, now: Date = Date()) -> String? {
        guard let quota else { return nil }
        var parts: [String] = []
        if let s = quota.sessionReset { parts.append("session dans \(ClaudeQuotaSource.countdown(to: s, from: now))") }
        if let w = quota.weeklyReset { parts.append("semaine dans \(ClaudeQuotaSource.countdown(to: w, from: now))") }
        return parts.isEmpty ? nil : "Reset : " + parts.joined(separator: " · ")
    }

    /// « MRR 1234€ · Total 12345€ » — n'affiche que les valeurs disponibles.
    nonisolated static func stripeLine(mrr: String?, total: String?) -> String {
        var parts: [String] = []
        if let mrr { parts.append("MRR \(mrr)") }
        if let total { parts.append("Total \(total)") }
        return parts.joined(separator: " · ")
    }
}
