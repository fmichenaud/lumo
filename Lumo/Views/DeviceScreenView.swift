import SwiftUI

/// Section « Écran » : la rotation de l'afficheur éditée comme une playlist.
/// Deux zones — « Dans la rotation » (ordonnée, glisser pour réordonner) et
/// « Disponibles » (sources éteintes) ; un toggle fait passer de l'une à l'autre.
/// Les réglages qui gouvernent la rotation (défilement, durée, transition)
/// vivent juste au-dessus de la liste.
struct DeviceScreenView: View {
    let device: Device
    @Environment(DeviceStore.self) var store
    @Environment(LiveAppsStation.self) var live
    @Environment(ConnectorsStation.self) var connectors
    @Environment(WeatherStation.self) var weatherStation
    @Environment(CalendarStation.self) var calendarStation
    @Environment(PomodoroStation.self) var pomodoro
    @Environment(DevicePoller.self) var poller
    var onResult: (String) -> Void = { _ in }

    // Rotation (loop du device) : sondée par DevicePoller, partagée avec la barre « à l'écran ».
    private var loopPositions: [String: Int] { poller.loop }
    private var currentApp: String? { poller.currentApp }

    @State private var nativeOn: [String: Bool] = [:]
    /// Customs masquées pendant la session (show:false) : restent proposées dans « Disponibles ».
    @State private var hiddenCustoms: Set<String> = []

    // Réglages de la rotation.
    @State private var autoTransition = true
    @State private var appTime = 5
    @State private var transitions: [String] = []
    @State private var transitionEffect = 0
    @State private var transitionSpeed: Double = 200

    // Sheets.
    @State private var editingConnector: Connector?
    @State private var showTemplates = false
    @State private var showWeatherConfig = false
    @State private var showCryptoConfig = false
    @State private var showCalendarConfig = false
    @State private var showTimerSheet = false
    @State private var editingCustom: CustomAppSelection?

    private struct CustomAppSelection: Identifiable {
        let name: String
        var id: String { name }
    }

    private var client: AwtrixClient { store.client(for: device) }

    // Apps gérées par ailleurs : tout le reste de la loop = app personnalisée.
    private let nativeApps: [(key: String, loop: String, title: String, icon: String, desc: String)] = [
        ("TIM", "Time", "Heure", "clock.fill", "Horloge de l'afficheur"),
        ("DAT", "Date", "Date", "calendar", "Date du jour"),
        ("TEMP", "Temperature", "Température", "thermometer.medium", "Capteur interne de l'afficheur"),
        ("HUM", "Humidity", "Humidité", "humidity.fill", "Capteur interne de l'afficheur"),
        ("BAT", "Battery", "Batterie", "battery.100", "Niveau de batterie de l'afficheur")
    ]
    private let managedNames: Set<String> = ["cpu", "ram", "crypto", "weather", "calendar", "timer",
                                             "time", "date", "temperature", "humidity", "battery", "notification"]

    var body: some View {
        // Une seule construction des lignes par passe de rendu, partagée par les deux cartes.
        let sources = partitionedSources()
        VStack(spacing: 14) {
            rotationSettingsBar
            rotationCard(sources.inRotation)
            availableCard(sources.available)
            addRow
        }
        .task(id: device.id) { await loadSettings() }
        .sheet(isPresented: $showTemplates) {
            TemplatePicker { template in
                showTemplates = false
                editingConnector = template.build()
            }
        }
        .sheet(item: $editingConnector) { connector in
            ConnectorEditor(device: device, connector: connector)
                .environment(connectors)
        }
        .sheet(isPresented: $showWeatherConfig) {
            WeatherConfigSheet(device: device, onResult: onResult)
                .environment(store)
                .environment(weatherStation)
        }
        .sheet(isPresented: $showCryptoConfig) {
            CryptoConfigSheet().environment(live)
        }
        .sheet(isPresented: $showCalendarConfig) {
            CalendarConfigSheet().environment(calendarStation)
        }
        .sheet(isPresented: $showTimerSheet) {
            PomodoroSheet().environment(pomodoro)
        }
        .sheet(item: $editingCustom) { selection in
            CustomAppSheet(name: selection.name,
                           client: client,
                           onShown: {
                               onResult("Affichage : « \(selection.name.capitalized) »")
                               Task { await poller.refreshNow(host: device.host) }
                           },
                           onDeleted: {
                               hiddenCustoms.remove(selection.name.lowercased())
                               onResult("« \(selection.name.capitalized) » supprimée de l'afficheur")
                               Task { await poller.refreshNow(host: device.host) }
                           })
        }
    }

    // MARK: - Modèle de ligne unifié

    private struct SourceRow: Identifiable {
        enum Kind {
            case native(key: String)
            case weather, calendar, cpu, ram, crypto, timer
            case connector(Connector)
            case custom(String)
        }
        let kind: Kind
        let loopName: String      // nom exact dans la loop (casse importante pour les natives)
        let title: String
        let icon: String
        let isOn: Bool
        let subtitle: String
        let liveValue: Bool       // sous-titre = donnée vivante (teinte dorée)
        let hasEditor: Bool
        let toggleDisabled: Bool
        var id: String { loopName.lowercased() }
    }

    private var allSources: [SourceRow] {
        var rows: [SourceRow] = []

        rows.append(SourceRow(
            kind: .weather, loopName: "weather", title: String(localized: "Météo"), icon: "cloud.sun.fill",
            isOn: weatherStation.autoEnabled,
            subtitle: weatherSubtitle, liveValue: weatherStation.autoEnabled && weatherStation.hasLocation,
            hasEditor: true, toggleDisabled: !weatherStation.hasLocation))

        rows.append(SourceRow(
            kind: .calendar, loopName: "calendar", title: String(localized: "Calendrier"), icon: "calendar",
            isOn: calendarStation.enabled,
            subtitle: calendarSubtitle, liveValue: calendarStation.enabled && calendarStation.lastError == nil,
            hasEditor: true, toggleDisabled: false))

        rows.append(SourceRow(
            kind: .cpu, loopName: "cpu", title: String(localized: "CPU du Mac"), icon: "cpu",
            isOn: live.cpuOn,
            subtitle: live.cpuOn ? "\(live.cpuValue)%" : String(localized: "Usage processeur du Mac"),
            liveValue: live.cpuOn, hasEditor: false, toggleDisabled: false))

        rows.append(SourceRow(
            kind: .ram, loopName: "ram", title: String(localized: "RAM du Mac"), icon: "memorychip",
            isOn: live.ramOn,
            subtitle: live.ramOn ? "\(live.ramValue)%" : String(localized: "Mémoire utilisée du Mac"),
            liveValue: live.ramOn, hasEditor: false, toggleDisabled: false))

        rows.append(SourceRow(
            kind: .crypto, loopName: "crypto", title: String(localized: "Crypto"), icon: "bitcoinsign",
            isOn: live.cryptoOn,
            subtitle: cryptoSubtitle, liveValue: live.cryptoOn,
            hasEditor: true, toggleDisabled: false))

        for c in connectors.connectors {
            rows.append(SourceRow(
                kind: .connector(c), loopName: c.appName,
                title: c.name.isEmpty ? String(localized: "Connecteur") : c.name,
                icon: connectorIcon(c),
                isOn: c.enabled,
                subtitle: connectorSubtitle(c), liveValue: c.enabled && connectors.lastValue[c.id] != nil,
                hasEditor: true, toggleDisabled: false))
        }

        for n in nativeApps {
            rows.append(SourceRow(
                kind: .native(key: n.key), loopName: n.loop, title: n.title, icon: n.icon,
                isOn: nativeOn[n.key] ?? false,
                subtitle: n.desc, liveValue: false,
                hasEditor: false, toggleDisabled: false))
        }

        // Minuteur : visible ici uniquement quand il tourne (l'app « timer » est
        // alors dans la loop) — la liste doit refléter tout ce qui défile réellement.
        // Son foyer de réglage reste la section Moments.
        if pomodoro.isActive || loopPositions["timer"] != nil {
            rows.append(SourceRow(
                kind: .timer, loopName: "timer", title: String(localized: "Minuteur"), icon: "timer",
                isOn: true,
                subtitle: pomodoro.statusText, liveValue: pomodoro.isActive,
                hasEditor: true, toggleDisabled: false))
        }

        // Apps personnalisées : celles de la loop + celles masquées pendant la session.
        let known = Set(rows.map(\.id))
        let customNames = Set(loopPositions.keys.filter { !known.contains($0.lowercased()) && !managedNames.contains($0.lowercased()) })
            .union(hiddenCustoms)
        for name in customNames.sorted() {
            let visible = !hiddenCustoms.contains(name.lowercased())
            rows.append(SourceRow(
                kind: .custom(name), loopName: name,
                title: name.capitalized, icon: "app.dashed",
                isOn: visible,
                subtitle: String(localized: "App personnalisée — créée dans Studio ou via l'API"),
                liveValue: false, hasEditor: true, toggleDisabled: false))
        }

        return rows
    }

    /// Sépare les sources en une seule passe : `allSources` est coûteuse (localisation,
    /// sous-titres vivants) et était reconstruite deux fois par rendu.
    private func partitionedSources() -> (inRotation: [SourceRow], available: [SourceRow]) {
        var inRotation: [SourceRow] = []
        var available: [SourceRow] = []
        for row in allSources {
            if row.isOn { inRotation.append(row) } else { available.append(row) }
        }
        inRotation.sort {
            (loopPositions[$0.loopName] ?? Int.max) < (loopPositions[$1.loopName] ?? Int.max)
        }
        return (inRotation, available)
    }

    // MARK: - Réglages de la rotation

    /// Barre des réglages de rotation, adaptative : une ligne quand la fenêtre est
    /// assez large, sinon deux (les libellés ne se coupent jamais en pleine lettre).
    private var rotationSettingsBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                rotationLabel
                autoTransitionToggle
                appTimeStepper
                transitionControls
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    rotationLabel
                    autoTransitionToggle
                    appTimeStepper
                    Spacer(minLength: 0)
                }
                HStack(spacing: 18) {
                    transitionControls
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.corner))
    }

    private var rotationLabel: some View {
        Label("Rotation", systemImage: "arrow.triangle.2.circlepath")
            .font(.caption.weight(.semibold)).tracking(0.6)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize()
    }

    private var autoTransitionToggle: some View {
        Toggle(isOn: Binding(get: { autoTransition }, set: { value in
            autoTransition = value
            Task { try? await client.setAutoTransition(value) }
        })) { Text("Défilement auto").font(.callout).fixedSize() }
    }

    private var appTimeStepper: some View {
        HStack(spacing: 8) {
            Text("\(appTime) s / app")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
            Stepper("", value: Binding(get: { appTime }, set: { value in
                appTime = value
                Task { try? await client.updateSettings(["ATIME": value]) }
            }), in: 1...60).labelsHidden()
        }
        .help("Durée d'affichage de chaque app avant de passer à la suivante")
    }

    // Effet et vitesse de transition : proposés une fois la liste chargée depuis le device.
    // Menu explicite plutôt que Picker : le popup du Picker perdait les titres
    // de ses items (rangées vides) dans ce contexte glassEffect sur macOS 26.
    @ViewBuilder private var transitionControls: some View {
        if !transitions.isEmpty {
            Menu {
                ForEach(Array(transitions.enumerated()), id: \.offset) { index, name in
                    Button {
                        transitionEffect = index
                        Task { try? await client.updateSettings(["TEFF": index]) }
                    } label: {
                        if index == transitionEffect {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(transitions.indices.contains(transitionEffect)
                         ? transitions[transitionEffect] : "—")
                        .font(.callout)
                        .fixedSize()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Theme.textPrimary)
            }
            .menuStyle(.button).buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke))
            .help("Effet de transition entre deux apps")

            HStack(spacing: 8) {
                Slider(value: $transitionSpeed, in: 100...2000, step: 50) { editing in
                    if !editing { Task { try? await client.updateSettings(["TSPEED": Int(transitionSpeed)]) } }
                }
                .tint(Theme.accent)
                .frame(width: 110)
                .controlSize(.small)
                Text("Durée · \(speedText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 90, alignment: .leading)
            }
            .frame(height: 24)
            .help("Durée de l'animation de transition entre deux apps")
        }
    }

    /// Durée de transition lisible : « 800 ms » ou « 1,2 s ».
    private var speedText: String {
        let ms = Int(transitionSpeed)
        if ms >= 1000 {
            return String(format: "%.1f s", transitionSpeed / 1000).replacingOccurrences(of: ".", with: ",")
        }
        return "\(ms) ms"
    }

    // MARK: - Cartes

    private func rotationCard(_ inRotation: [SourceRow]) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(localized: "Dans la rotation").uppercased())
                    .font(.caption.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                Text("— glisse pour ordonner")
                    .font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.7))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Theme.online).frame(width: 6, height: 6)
                    Text("en direct").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }

            if inRotation.isEmpty {
                Text("Rien dans la rotation — active une source ci-dessous.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                List {
                    ForEach(inRotation) { row in
                        sourceRow(row, draggable: true)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.stroke)
                            .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
                    }
                    .onMove { source, destination in moveRows(inRotation, from: source, to: destination) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(inRotation.count) * 50)
            }
        }
        .card()
    }

    private func availableCard(_ available: [SourceRow]) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(localized: "Disponibles").uppercased())
                    .font(.caption.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            if available.isEmpty {
                Text("Tout est déjà dans la rotation.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(available.enumerated()), id: \.element.id) { index, row in
                        sourceRow(row, draggable: false)
                            .padding(.vertical, 6)
                        if index < available.count - 1 {
                            Divider().overlay(Theme.stroke)
                        }
                    }
                }
                .opacity(0.8)
            }

        }
        .card()
    }

    private var addRow: some View {
        HStack(spacing: 14) {
            Button { showTemplates = true } label: {
                Label("Ajouter un connecteur", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .help("Brancher un service externe (compte ou clé API)")

            Button {
                store.selectedSection = .studio
            } label: {
                Label("Créer un affichage dans Studio", systemImage: "paintpalette")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Lignes

    @ViewBuilder
    private func sourceRow(_ row: SourceRow, draggable: Bool) -> some View {
        let isCurrent = currentApp?.lowercased() == row.loopName.lowercased()
        HStack(spacing: 12) {
            if draggable {
                Image(systemName: "line.3.horizontal")
                    .font(.caption).foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
            iconBadge(row.icon, active: isCurrent)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.title).foregroundStyle(Theme.textPrimary)
                    if isCurrent {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
                if isCurrent {
                    Text("À l'écran").font(.caption2).foregroundStyle(Theme.accent)
                } else {
                    Text(LocalizedStringKey(row.subtitle))
                        .font(.caption2)
                        .foregroundStyle(row.liveValue ? Theme.accent : Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if row.hasEditor {
                editButton { openEditor(row) }
            }
            Toggle("", isOn: Binding(get: { row.isOn }, set: { toggle(row, $0) }))
                .labelsHidden().tint(Theme.accent)
                .disabled(row.toggleDisabled)
        }
    }

    private func editButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "pencil") }
            .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            .help("Configurer")
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

    // MARK: - Sous-titres

    private var weatherSubtitle: String {
        if !weatherStation.hasLocation { return String(localized: "Choisis une ville pour commencer (✎)") }
        return weatherStation.locationLabel + (weatherStation.weather.map { " · \($0.tempText)" } ?? "")
    }

    private var calendarSubtitle: String {
        guard calendarStation.enabled else { return String(localized: "Prochain événement de tes calendriers") }
        if let error = calendarStation.lastError { return error }
        return calendarStation.nextEventText ?? String(localized: "Aucun événement à venir")
    }

    private var cryptoSubtitle: String {
        guard live.cryptoOn, let p = live.cryptoPrice else { return String(localized: "Cours crypto (CoinGecko)") }
        let price = p >= 100 ? String(Int(p.rounded())) : String(format: "%.2f", p)
        return "\(live.coinSymbol) \(price)\(live.currencySymbol)"
    }

    private func connectorSubtitle(_ c: Connector) -> String {
        if c.enabled, let v = connectors.lastValue[c.id] { return connectors.renderedText(c, value: v) }
        switch c.special {
        case .claudeQuota: return String(localized: "Quota Claude Code")
        case .stripeMRR:   return String(localized: "Revenu mensuel Stripe")
        case .stripeTotal: return String(localized: "Encaissements Stripe")
        case nil:
            if let host = URL(string: c.url)?.host { return host }
            return String(localized: "Service connecté")
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

    // MARK: - Actions

    private func toggle(_ row: SourceRow, _ on: Bool) {
        switch row.kind {
        case .weather:  weatherStation.setAuto(on)
        case .calendar: calendarStation.setEnabled(on)
        case .cpu:      live.setCPU(on)
        case .ram:      live.setRAM(on)
        case .crypto:   live.setCrypto(on)
        case .timer:
            // Éteindre la ligne = arrêter le minuteur (l'app « timer » quitte la loop).
            if !on { pomodoro.stop() }
        case .connector(let c): connectors.setEnabled(c, on)
        case .native(let key):
            nativeOn[key] = on
            Task {
                try? await client.updateSettings([key: on])
                try? await client.setNativeAppVisible(row.loopName, show: on)
                await poller.refreshNow(host: device.host)
            }
        case .custom(let name):
            if on { hiddenCustoms.remove(name.lowercased()) } else { hiddenCustoms.insert(name.lowercased()) }
            Task {
                try? await client.setNativeAppVisible(name, show: on)
                await poller.refreshNow(host: device.host)
            }
        }
    }

    private func openEditor(_ row: SourceRow) {
        switch row.kind {
        case .weather:  showWeatherConfig = true
        case .calendar: showCalendarConfig = true
        case .crypto:   showCryptoConfig = true
        case .timer:    showTimerSheet = true
        case .connector(let c): editingConnector = c
        case .custom(let name): editingCustom = CustomAppSelection(name: name)
        case .cpu, .ram, .native: break
        }
    }

    /// Réordonnancement inline : pousse l'ordre complet de la loop sur le device.
    private func moveRows(_ rows: [SourceRow], from source: IndexSet, to destination: Int) {
        var rows = rows
        rows.move(fromOffsets: source, toOffset: destination)
        // Seules les apps réellement présentes dans la loop sont envoyées.
        let order = rows.map(\.loopName).filter { loopPositions[$0] != nil }
        // Mise à jour optimiste des positions pour un rendu immédiat.
        poller.applyOptimisticOrder(order)
        Task {
            do {
                try await client.setLoopOrder(order)
                onResult("Ordre de la rotation mis à jour")
            } catch {
                await poller.refreshNow(host: device.host)
                onResult("Impossible d'appliquer l'ordre : \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Données

    private func loadSettings() async {
        if let s = try? await client.fetchSettings() {
            if let t = s.ATRANS { autoTransition = t }
            if let a = s.ATIME { appTime = a }
            if let te = s.TEFF { transitionEffect = te }
            if let ts = s.TSPEED { transitionSpeed = Double(min(2000, max(100, ts))) }
            nativeOn = ["TIM": s.TIM ?? false, "DAT": s.DAT ?? false, "TEMP": s.TEMP ?? false,
                        "HUM": s.HUM ?? false, "BAT": s.BAT ?? false]
        }
        if let list = try? await client.fetchTransitions() { transitions = list }
    }
}
