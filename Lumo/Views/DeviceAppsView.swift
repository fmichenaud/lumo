import SwiftUI

/// Hub unique de l'affichage : tout ce qui peut tourner à l'écran, activable et configurable
/// au même endroit — intégrations (météo, Mac, crypto, connecteurs), apps natives du firmware,
/// et apps custom restantes. Rafraîchi en direct.
struct DeviceAppsView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var live: LiveAppsStation
    @EnvironmentObject var connectors: ConnectorsStation
    @EnvironmentObject var weatherStation: WeatherStation
    @EnvironmentObject var calendarStation: CalendarStation
    @EnvironmentObject var pomodoro: PomodoroStation
    var onResult: (String) -> Void = { _ in }

    @State private var loopApps: [LoopApp] = []
    @State private var current: String?
    @State private var nativeOn: [String: Bool] = [:]
    @State private var editingConnector: Connector?
    @State private var showTemplates = false
    @State private var showWeatherConfig = false
    @State private var showCryptoConfig = false
    @State private var showReorder = false
    @State private var showTimerSheet = false

    private var client: AwtrixClient { store.client(for: device) }

    struct LoopApp: Identifiable { let name: String; let position: Int; var id: String { name } }

    // Apps natives : (clé réglage, nom dans la loop — sensible à la casse, titre, icône)
    private let natives: [(key: String, loop: String, title: String, icon: String)] = [
        ("TIM", "Time", "Heure", "clock.fill"),
        ("DAT", "Date", "Date", "calendar"),
        ("TEMP", "Temperature", "Température", "thermometer.medium"),
        ("HUM", "Humidity", "Humidité", "humidity.fill"),
        ("BAT", "Battery", "Batterie", "battery.100")
    ]
    private let managedNames: Set<String> = ["cpu", "ram", "crypto", "weather", "calendar", "timer", "time", "date", "temperature", "humidity", "battery", "notification"]

    var body: some View {
        VStack(spacing: 14) {
            header

            groupLabel("Intégrations")
            weatherRow
            toggleRow(icon: "calendar", title: "Calendrier", loopName: "calendar",
                      detail: calendarDetail,
                      isOn: calendarStation.enabled, set: { calendarStation.setEnabled($0) })
            toggleRow(icon: "cpu", title: "CPU du Mac", loopName: "cpu",
                      detail: live.cpuOn ? "\(live.cpuValue)%" : nil,
                      isOn: live.cpuOn, set: { live.setCPU($0) })
            toggleRow(icon: "memorychip", title: "RAM du Mac", loopName: "ram",
                      detail: live.ramOn ? "\(live.ramValue)%" : nil,
                      isOn: live.ramOn, set: { live.setRAM($0) })
            toggleRow(icon: "bitcoinsign", title: "Crypto", loopName: "crypto",
                      detail: cryptoDetail,
                      isOn: live.cryptoOn, set: { live.setCrypto($0) },
                      onEdit: { showCryptoConfig = true })
            ForEach(connectors.connectors) { c in
                toggleRow(icon: connectorIcon(c),
                          title: c.name.isEmpty ? "Connecteur" : c.name,
                          loopName: c.appName,
                          detail: connectors.lastValue[c.id].map { c.renderedText(value: $0) },
                          isOn: c.enabled, set: { connectors.setEnabled(c, $0) },
                          onEdit: { editingConnector = c })
            }
            Button { showTemplates = true } label: {
                Label("Ajouter un connecteur", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .frame(maxWidth: .infinity, alignment: .leading)

            groupLabel("Apps de l'afficheur")
            ForEach(natives, id: \.key) { n in
                toggleRow(icon: n.icon, title: n.title, loopName: n.loop, detail: nil,
                          isOn: nativeOn[n.key] ?? false, set: { setNative(n.key, n.loop, $0) })
            }

            groupLabel("Outils")
            timerRow

            if !otherApps.isEmpty {
                groupLabel("Autres apps")
                ForEach(otherApps) { customRow($0) }
            }
        }
        .card()
        .task(id: device.id) {
            if let s = try? await client.fetchSettings() { applyNative(s) }
            while !Task.isCancelled {
                await loadLoop()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .sheet(isPresented: $showTemplates) {
            TemplatePicker { template in
                showTemplates = false
                editingConnector = template.build()
            }
        }
        .sheet(item: $editingConnector) { connector in
            ConnectorEditor(device: device, connector: connector)
                .environmentObject(connectors)
        }
        .sheet(isPresented: $showWeatherConfig) {
            WeatherConfigSheet(device: device, onResult: onResult)
                .environmentObject(store)
                .environmentObject(weatherStation)
        }
        .sheet(isPresented: $showCryptoConfig) {
            CryptoConfigSheet().environmentObject(live)
        }
        .sheet(isPresented: $showReorder) {
            ReorderSheet(client: client, onResult: onResult)
        }
        .sheet(isPresented: $showTimerSheet) {
            PomodoroSheet().environmentObject(pomodoro)
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(String(localized: String.LocalizationValue(text)).uppercased())
            .font(.caption2.weight(.semibold)).tracking(0.8)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var header: some View {
        HStack {
            Text("CE QUI TOURNE À L'ÉCRAN")
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { showReorder = true } label: {
                Label("Ordonner", systemImage: "arrow.up.arrow.down")
                    .font(.caption2)
            }
            .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            .help("Réordonner la rotation")
            HStack(spacing: 5) {
                Circle().fill(Theme.online).frame(width: 6, height: 6)
                Text("en direct").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func connectorIcon(_ c: Connector) -> String {
        switch c.special {
        case .claudeQuota: return "sparkles"
        case .stripeMRR:   return "creditcard"
        case .stripeTotal: return "banknote"
        case nil:          return "antenna.radiowaves.left.and.right"
        }
    }

    /// Sous-titre de la ligne Calendrier : erreur d'accès, prochain événement, ou rien à venir.
    private var calendarDetail: String? {
        guard calendarStation.enabled else { return nil }
        if let error = calendarStation.lastError { return error }
        return calendarStation.nextEventText ?? String(localized: "Aucun événement à venir")
    }

    private var cryptoDetail: String? {
        guard live.cryptoOn, let p = live.cryptoPrice else { return nil }
        let price = p >= 100 ? String(Int(p.rounded())) : String(format: "%.2f", p)
        return "\(live.coinSymbol) \(price)\(live.currencySymbol)"
    }

    /// Apps présentes dans la loop qui ne sont pas des apps gérées (intégrations/natives) ni transitoires.
    private var otherApps: [LoopApp] {
        let connectorNames = Set(connectors.connectors.map { $0.appName.lowercased() })
        return loopApps.filter {
            !managedNames.contains($0.name.lowercased()) && !connectorNames.contains($0.name.lowercased())
        }
    }

    // MARK: - Lignes

    private var weatherRow: some View {
        let isCurrent = current?.lowercased() == "weather"
        let subtitle: String
        if !weatherStation.hasLocation {
            subtitle = String(localized: "Choisis une ville pour commencer")
        } else if isCurrent {
            subtitle = String(localized: "À l'écran maintenant")
        } else {
            subtitle = weatherStation.locationLabel
                + (weatherStation.weather.map { " · \($0.tempText)" } ?? "")
        }
        return HStack(spacing: 12) {
            iconBadge("cloud.sun.fill", active: isCurrent)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Météo").foregroundStyle(Theme.textPrimary)
                    if isCurrent {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
                Text(subtitle).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { showWeatherConfig = true } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            Toggle("", isOn: Binding(get: { weatherStation.autoEnabled },
                                     set: { weatherStation.setAuto($0) }))
                .labelsHidden().tint(Theme.accent)
                .disabled(!weatherStation.hasLocation)
        }
    }

    /// Ligne « Minuteur » : sous-titre = état, contrôles play/pause et stop quand actif,
    /// clic sur la ligne (ou crayon) → sheet de configuration.
    private var timerRow: some View {
        let isCurrent = current?.lowercased() == "timer"
        return HStack(spacing: 12) {
            iconBadge("timer", active: isCurrent || pomodoro.isActive)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Minuteur").foregroundStyle(Theme.textPrimary)
                    if isCurrent {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
                Text(pomodoro.statusText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(pomodoro.isActive ? Theme.accent : Theme.textSecondary)
            }
            Spacer()
            if pomodoro.isActive {
                Button {
                    if pomodoro.isRunning { pomodoro.pause() } else { pomodoro.resume() }
                } label: {
                    Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                Button { pomodoro.stop() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.plain).foregroundStyle(.red.opacity(0.85))
            }
            Button { showTimerSheet = true } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { showTimerSheet = true }
    }

    private func toggleRow(icon: String, title: String, loopName: String, detail: String?,
                           isOn: Bool, set: @escaping (Bool) -> Void,
                           onEdit: (() -> Void)? = nil) -> some View {
        let isCurrent = current?.lowercased() == loopName.lowercased()
        return HStack(spacing: 12) {
            iconBadge(icon, active: isCurrent)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(title)).foregroundStyle(Theme.textPrimary)
                    if isCurrent {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
                if isCurrent {
                    Text("À l'écran maintenant").font(.caption2).foregroundStyle(Theme.textSecondary)
                } else if let detail {
                    Text(detail).font(.caption2).foregroundStyle(Theme.accent)
                } else {
                    Text(LocalizedStringKey(isOn ? "Active" : "Inactive"))
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if let onEdit {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
            Toggle("", isOn: Binding(get: { isOn }, set: set)).labelsHidden().tint(Theme.accent)
        }
    }

    private func customRow(_ app: LoopApp) -> some View {
        let isCurrent = current == app.name
        return HStack(spacing: 12) {
            iconBadge("app.dashed", active: isCurrent)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name.capitalized).foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(isCurrent ? "À l'écran maintenant" : "App personnalisée"))
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Afficher") { Task { await show(app) } }
                .buttonStyle(PillButtonStyle(prominent: false)).controlSize(.small)
            Button { Task { await delete(app) } } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.red.opacity(0.85))
        }
    }

    private func iconBadge(_ icon: String, active: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(active ? Theme.accent.opacity(0.18) : Color.white.opacity(0.05))
                .frame(width: 32, height: 32)
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
        }
    }

    // MARK: - Données

    private func loadLoop() async {
        guard let loop = try? await client.fetchLoop() else { return }
        loopApps = loop.map { LoopApp(name: $0.key, position: $0.value) }.sorted { $0.position < $1.position }
        current = try? await client.fetchStats().app
    }

    private func applyNative(_ s: AwtrixSettings) {
        nativeOn = ["TIM": s.TIM ?? false, "DAT": s.DAT ?? false, "TEMP": s.TEMP ?? false,
                    "HUM": s.HUM ?? false, "BAT": s.BAT ?? false]
    }

    /// Toggle natif fluide : /api/settings persiste le choix pour les prochains boots,
    /// /api/apps l'applique immédiatement dans la rotation (pas de reboot).
    private func setNative(_ key: String, _ loopName: String, _ on: Bool) {
        nativeOn[key] = on
        Task {
            try? await client.updateSettings([key: on])
            try? await client.setNativeAppVisible(loopName, show: on)
            await loadLoop()
        }
    }

    private func show(_ app: LoopApp) async {
        try? await client.switchApp(name: app.name)
        current = app.name
        onResult("Affichage : « \(app.name.capitalized) »")
    }

    private func delete(_ app: LoopApp) async {
        try? await client.deleteCustomApp(name: app.name)
        onResult("« \(app.name.capitalized) » supprimée")
        await loadLoop()
    }
}

/// Sheet de réordonnancement de la rotation : glisser-déposer les apps de la loop,
/// l'ordre est appliqué à chaud sur l'afficheur à chaque déplacement (POST /api/apps).
private struct ReorderSheet: View {
    let client: AwtrixClient
    var onResult: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var names: [String] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ordre de la rotation").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    Text("Glisse les apps pour changer leur ordre — appliqué immédiatement.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }

            if !loaded {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .frame(height: 120)
            } else if names.isEmpty {
                Text("Aucune app dans la rotation.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    ForEach(Array(names.enumerated()), id: \.element) { index, name in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 18, alignment: .trailing)
                            Text(name.capitalized).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .font(.caption).foregroundStyle(Theme.textSecondary.opacity(0.6))
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.stroke)
                    }
                    .onMove(perform: move)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(names.count) * 34 + 16, 320))
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.background)
        .task {
            await reload()
            loaded = true
        }
    }

    /// Recharge la loop actuelle et trie par position.
    private func reload() async {
        guard let loop = try? await client.fetchLoop() else { return }
        names = loop.sorted { $0.value < $1.value }.map { $0.key }
    }

    /// Applique le déplacement localement puis pousse l'ordre complet sur le device.
    private func move(from source: IndexSet, to destination: Int) {
        names.move(fromOffsets: source, toOffset: destination)
        let order = names
        Task {
            do {
                try await client.setLoopOrder(order)
                onResult("Ordre de la rotation mis à jour")
            } catch {
                // En cas d'échec, on resynchronise avec l'état réel du device.
                await reload()
                onResult("Impossible d'appliquer l'ordre : \(error.localizedDescription)")
            }
        }
    }
}

/// Sheet du minuteur : durées rapides ou custom, mode Pomodoro, message de fin,
/// temps restant en grand et bouton Démarrer/Arrêter.
private struct PomodoroSheet: View {
    @EnvironmentObject var pomodoro: PomodoroStation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minuteur").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    Text("Compte à rebours affiché sur la matrice, sonnerie à zéro.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }

            // Temps restant en grand quand le minuteur est actif.
            if pomodoro.isActive {
                VStack(spacing: 4) {
                    Text(PomodoroStation.timeText(Int(pomodoro.remaining.rounded())))
                        .font(.system(size: 46, weight: .bold).monospacedDigit())
                        .foregroundStyle(pomodoro.isRunning ? Theme.textPrimary : Theme.textSecondary)
                    if pomodoro.pomodoroMode {
                        Text(pomodoro.onBreak
                             ? "Pause · cycle \(pomodoro.cycleCount) terminé"
                             : "Travail · cycle \(pomodoro.cycleCount + 1)")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    } else if !pomodoro.isRunning {
                        Text("En pause").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Choix de la durée (désactivé pendant le décompte et en mode Pomodoro).
            HStack(spacing: 8) {
                ForEach(PomodoroStation.presets, id: \.self) { m in
                    Button("\(m) min") { pomodoro.setMinutes(m) }
                        .buttonStyle(PillButtonStyle(prominent: pomodoro.customMinutes == m))
                        .controlSize(.small)
                }
                Spacer()
                Stepper(value: Binding(get: { pomodoro.customMinutes },
                                       set: { pomodoro.setMinutes($0) }), in: 1...180) {
                    Text("\(pomodoro.customMinutes) min")
                        .font(.callout.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                }
            }
            .disabled(pomodoro.isActive || pomodoro.pomodoroMode)
            .opacity(pomodoro.isActive || pomodoro.pomodoroMode ? 0.5 : 1)

            Toggle(isOn: Binding(get: { pomodoro.pomodoroMode },
                                 set: { pomodoro.setPomodoroMode($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mode Pomodoro").foregroundStyle(Theme.textPrimary)
                    Text("Travail 25 min et pause 5 min, enchaînés.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            .toggleStyle(.switch).tint(Theme.accent)
            .disabled(pomodoro.isActive)

            TextField("Message de fin", text: Binding(get: { pomodoro.endMessage },
                                                      set: { pomodoro.setEndMessage($0) }))
                .textFieldStyle(.roundedBorder)

            if pomodoro.isActive {
                Button {
                    pomodoro.stop()
                } label: {
                    Label("Arrêter", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            } else {
                Button {
                    pomodoro.start()
                } label: {
                    Label("Démarrer", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.background)
    }
}

/// Sheet de configuration de l'intégration Crypto : choix de la devise et de la monnaie.
private struct CryptoConfigSheet: View {
    @EnvironmentObject var live: LiveAppsStation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crypto").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    Text("Cours mis à jour toutes les 60 s (CoinGecko).")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 12) {
                Picker("Crypto", selection: Binding(get: { live.coinID }, set: { live.setCoin($0) })) {
                    ForEach(DataService.coins) { Text($0.symbol).tag($0.id) }
                }
                .frame(width: 160)
                Picker("Devise", selection: Binding(get: { live.currency }, set: { live.setCurrency($0) })) {
                    Text("EUR").tag("eur"); Text("USD").tag("usd")
                }
                .frame(width: 140)
                Spacer()
                if live.cryptoOn, let p = live.cryptoPrice {
                    Text("\(live.coinSymbol) \(p >= 100 ? String(Int(p.rounded())) : String(format: "%.2f", p))\(live.currencySymbol)")
                        .font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(Theme.background)
    }
}
