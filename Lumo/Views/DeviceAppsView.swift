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
    @EnvironmentObject var claude: ClaudeUsageStation
    @EnvironmentObject var stripe: StripeStation
    var onResult: (String) -> Void = { _ in }

    @State private var loopApps: [LoopApp] = []
    @State private var current: String?
    @State private var nativeOn: [String: Bool] = [:]
    @State private var editingConnector: Connector?
    @State private var showTemplates = false
    @State private var showWeatherConfig = false
    @State private var showCryptoConfig = false
    @State private var showClaudeConfig = false
    @State private var showStripeConfig = false

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
    private let managedNames: Set<String> = ["cpu", "ram", "crypto", "weather", "claude", "mrr", "time", "date", "temperature", "humidity", "battery", "notification"]

    var body: some View {
        VStack(spacing: 14) {
            header

            groupLabel("Intégrations")
            weatherRow
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
            toggleRow(icon: "sparkles", title: "Quota Claude Code", loopName: "claude",
                      detail: claude.enabled ? (claude.lastError ?? claude.summaryText) : nil,
                      isOn: claude.enabled, set: { claude.setEnabled($0) },
                      onEdit: { showClaudeConfig = true })
            toggleRow(icon: "creditcard", title: "MRR Stripe", loopName: "mrr",
                      detail: stripe.enabled ? (stripe.lastError ?? stripe.summaryText) : nil,
                      isOn: stripe.enabled,
                      set: { on in
                          // Pas de clé → on ouvre la config au lieu d'activer dans le vide.
                          if on && stripe.apiKey.isEmpty { showStripeConfig = true }
                          else { stripe.setEnabled(on) }
                      },
                      onEdit: { showStripeConfig = true })
            ForEach(connectors.connectors) { c in
                toggleRow(icon: "antenna.radiowaves.left.and.right",
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
        .sheet(isPresented: $showClaudeConfig) {
            ClaudeConfigSheet().environmentObject(claude)
        }
        .sheet(isPresented: $showStripeConfig) {
            StripeConfigSheet().environmentObject(stripe)
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
            HStack(spacing: 5) {
                Circle().fill(Theme.online).frame(width: 6, height: 6)
                Text("en direct").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
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

/// Sheet de l'intégration Claude Code : choix de l'affichage + explication de l'accès Trousseau.
private struct ClaudeConfigSheet: View {
    @EnvironmentObject var claude: ClaudeUsageStation
    @Environment(\.dismiss) private var dismiss
    @State private var refreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quota Claude Code").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    Text("Affiche l'utilisation de tes limites — session (5 h) et semaine — mise à jour toutes les 60 s.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 12) {
                Picker("Afficher", selection: Binding(get: { claude.display }, set: { claude.setDisplay($0) })) {
                    ForEach(ClaudeUsageStation.Display.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 260)
                Spacer()
                Button {
                    refreshing = true
                    Task { await claude.refresh(); refreshing = false }
                } label: {
                    if refreshing { ProgressView().controlSize(.small) }
                    else { Label("Actualiser", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(PillButtonStyle(prominent: false)).controlSize(.small)
            }

            if let err = claude.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else if let text = claude.summaryText {
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Theme.online)
            }

            Text("Lumo lit le token de Claude Code dans le Trousseau (macOS te demandera d'autoriser l'accès une fois — choisis « Toujours autoriser »). Aucune clé à saisir.")
                .font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 470)
        .background(Theme.background)
    }
}

/// Sheet de l'intégration Stripe : clé API restreinte + test.
private struct StripeConfigSheet: View {
    @EnvironmentObject var stripe: StripeStation
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MRR Stripe").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    Text("Revenu mensuel récurrent, calculé depuis tes abonnements actifs · mise à jour toutes les 30 min.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Clé API").font(.caption2).foregroundStyle(Theme.textSecondary)
                SecureField("rk_live_… ou sk_live_…", text: $key)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    Text("Recommandé : une clé restreinte avec la seule permission « Subscriptions : lecture ».")
                        .font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    // Ouvre le Dashboard sur la création d'une clé restreinte pré-remplie.
                    Link(destination: URL(string: "https://dashboard.stripe.com/apikeys/create?name=Lumo&permissions%5B%5D=rak_subscription_read")!) {
                        Label("Créer la clé", systemImage: "arrow.up.right.square")
                            .font(.caption2)
                    }
                    .foregroundStyle(Theme.accent)
                    .help("Ouvre Stripe avec le formulaire pré-rempli : nom « Lumo », permission Subscriptions en lecture")
                }
            }

            HStack(spacing: 10) {
                Button {
                    stripe.setAPIKey(key)
                    testing = true
                    Task { await stripe.refresh(); testing = false }
                } label: {
                    if testing { ProgressView().controlSize(.small) }
                    else { Label("Enregistrer et tester", systemImage: "checkmark.circle") }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)

                if let err = stripe.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                } else if let text = stripe.summaryText {
                    Label(text, systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Theme.online)
                }
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 500)
        .background(Theme.background)
        .onAppear { key = stripe.apiKey }
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
