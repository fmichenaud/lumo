import SwiftUI

/// Section « Moments » : tout ce qui interrompt la rotation de l'écran —
/// notification manuelle, règles d'alerte (seuil ou horaire), minuteur,
/// LED témoins et passerelle de notifications.
struct MomentsView: View {
    let device: Device
    var onResult: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NotificationCard(device: device, onResult: onResult)
            RulesCard(device: device, onResult: onResult)
            TimerCard()
            IndicatorsCard(device: device, onResult: onResult)
            GatewayCard()
        }
    }
}

// MARK: - Notification manuelle

/// Envoi d'un message ponctuel par-dessus la rotation — l'action de base d'un
/// afficheur, désormais au premier niveau (elle était repliée dans un disclosure).
private struct NotificationCard: View {
    let device: Device
    @Environment(DeviceStore.self) var store
    var onResult: (String) -> Void = { _ in }

    @State private var text = ""
    @State private var color = Theme.accent
    @State private var icon = ""
    @State private var effect = ""
    @State private var sound = ""
    @State private var hold = false
    @State private var wakeup = true
    @State private var effects: [String] = []
    @State private var showAdvanced = false

    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Notification", icon: "bell.badge.fill",
                       desc: "Affiche un message par-dessus l'écran quelques secondes, puis disparaît.")
            HStack(spacing: 10) {
                TextField("Message à afficher", text: $text).textFieldStyle(.roundedBorder)
                ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
                IconThumbnail(host: device.host, iconID: icon)
                TextField("Icône", text: $icon).textFieldStyle(.roundedBorder).frame(width: 60)
                Button { Task { await send() } } label: {
                    Label("Envoyer", systemImage: "paperplane.fill")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(text.isEmpty && icon.isEmpty)
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    optionRow("Effet de fond", "Animation derrière le texte") {
                        Picker("", selection: $effect) {
                            Text("Aucun").tag("")
                            ForEach(effects, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 160)
                    }
                    optionRow("Son", "Nom d'une mélodie présente sur l'appareil") {
                        TextField("ex. alarm", text: $sound).textFieldStyle(.roundedBorder).frame(width: 160)
                    }
                    optionRow("Garder affichée", "Reste jusqu'à appui sur le bouton central") {
                        Toggle("", isOn: $hold).labelsHidden().tint(Theme.accent)
                    }
                    optionRow("Réveiller l'écran", "Allume la dalle si elle est éteinte") {
                        Toggle("", isOn: $wakeup).labelsHidden().tint(Theme.accent)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Options avancées").font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
        .task { effects = (try? await client.fetchEffects()) ?? [] }
    }

    private func send() async {
        var p = PushPayload()
        p.text = text.isEmpty ? nil : text
        p.color = color.hexString
        let trimmedIcon = icon.trimmingCharacters(in: .whitespaces)
        if !trimmedIcon.isEmpty { p.icon = trimmedIcon }
        if !effect.isEmpty { p.effect = effect }
        if !sound.isEmpty { p.sound = sound }
        p.hold = hold
        p.wakeup = wakeup
        do {
            try await client.notify(p)
            onResult("Notification envoyée")
        } catch {
            onResult("Échec de la notification")
        }
    }
}

// MARK: - Règles d'alerte

private struct RulesCard: View {
    let device: Device
    @Environment(AlertsStation.self) var alerts
    @Environment(ConnectorsStation.self) var connectors
    var onResult: (String) -> Void = { _ in }

    @State private var editing: AlertRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Règles d'alerte", icon: "bolt.badge.clock.fill",
                       desc: "Surveille un seuil ou une heure, et déclenche notification, son ou LED.")

            if alerts.rules.isEmpty {
                VStack(spacing: 6) {
                    Text("Aucune règle")
                        .font(.callout).foregroundStyle(Theme.textSecondary)
                    Text("Exemple : « si le CPU du Mac dépasse 90 %, affiche une alerte rouge ».")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                ForEach(alerts.rules) { ruleRow($0) }
            }

            Button { editing = AlertRule() } label: {
                Label("Ajouter une règle", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
        }
        .card()
        .sheet(item: $editing) { rule in
            RuleEditor(device: device, rule: rule)
                .environment(alerts)
                .environment(connectors)
        }
    }

    private func ruleRow(_ rule: AlertRule) -> some View {
        let isActive = alerts.active.contains(rule.id)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? Color.red.opacity(0.2) : Color.white.opacity(0.05))
                    .frame(width: 32, height: 32)
                Image(systemName: rule.trigger == .schedule ? "clock.badge" : rule.metric.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isActive ? .red : Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.conditionSummary(connectorName: connectorName(rule)))
                    .foregroundStyle(Theme.textPrimary)
                if isActive {
                    Text("Alerte en cours").font(.caption2).foregroundStyle(.red)
                } else if rule.trigger == .schedule {
                    Text(rule.enabled ? "Se déclenchera à l'heure prévue" : "En pause")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                } else if let v = alerts.lastValues[rule.id] {
                    Text("Actuellement : \(AlertRule.format(v))\(rule.metric.unit)")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                } else {
                    Text(rule.enabled ? "En attente de données…" : "En pause")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Button("Tester") { Task { await alerts.test(rule); onResult("Alerte testée") } }
                .buttonStyle(PillButtonStyle(prominent: false)).controlSize(.small)
            Button { editing = rule } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { alerts.setEnabled(rule, $0) }))
                .labelsHidden().tint(Theme.accent)
        }
    }

    private func connectorName(_ rule: AlertRule) -> String? {
        guard rule.metric == .connector, let id = rule.connectorID else { return nil }
        return connectors.connectors.first { $0.id == id }?.name
    }
}

// MARK: - Minuteur

private struct TimerCard: View {
    @Environment(PomodoroStation.self) var pomodoro
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Minuteur", icon: "timer",
                       desc: "Compte à rebours (ou Pomodoro) affiché sur la matrice, sonnerie à zéro.")
            HStack(spacing: 12) {
                if pomodoro.isActive {
                    Text(PomodoroStation.timeText(Int(pomodoro.remaining.rounded())))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(pomodoro.isRunning ? Theme.accent : Theme.textSecondary)
                    Button {
                        if pomodoro.isRunning { pomodoro.pause() } else { pomodoro.resume() }
                    } label: {
                        Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    Button { pomodoro.stop() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(.plain).foregroundStyle(.red.opacity(0.85))
                } else {
                    Button {
                        pomodoro.start()
                    } label: {
                        Label("Démarrer \(pomodoro.pomodoroMode ? 25 : pomodoro.customMinutes) min",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false)).controlSize(.small)
                }
                Spacer()
                Button { showSheet = true } label: {
                    Label("Régler", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
        .sheet(isPresented: $showSheet) { PomodoroSheet().environment(pomodoro) }
    }
}

// MARK: - LED témoins

private struct IndicatorsCard: View {
    let device: Device
    @Environment(DeviceStore.self) var store
    var onResult: (String) -> Void = { _ in }

    @State private var indicatorColors: [Color] = [.red, .green, Theme.accent]

    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("LED témoins", icon: "circle.lefthalf.filled",
                       desc: "Les 3 petites LED du bord de l'écran — pratiques comme témoins de statut.")
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 12) {
                    ColorPicker("", selection: $indicatorColors[i], supportsOpacity: false).labelsHidden()
                    Text("LED \(i + 1)").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Allumer") { Task { try? await client.setIndicator(i + 1, rgb: indicatorColors[i].rgbArray); onResult("LED \(i + 1) allumée") } }
                        .buttonStyle(PillButtonStyle(prominent: false)).controlSize(.small)
                    Button("Éteindre") { Task { try? await client.clearIndicator(i + 1); onResult("LED \(i + 1) éteinte") } }
                        .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .card()
    }
}

// MARK: - Passerelle de notifications

/// La passerelle reçoit des messages d'autres apps (Raccourcis, scripts, curl…)
/// et les affiche : une source de « moments ». Port et exemples dans sa sheet.
private struct GatewayCard: View {
    @Environment(NotificationGateway.self) var gateway
    @State private var showConfig = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cardHeader("Passerelle de notifications", icon: "tray.and.arrow.down.fill",
                       desc: subtitle)
            Button { showConfig = true } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                .help("Port d'écoute et exemples d'utilisation")
            Toggle("", isOn: Binding(get: { gateway.enabled }, set: { gateway.setEnabled($0) }))
                .labelsHidden().tint(Theme.accent)
        }
        .card()
        .sheet(isPresented: $showConfig) { GatewaySheet().environment(gateway) }
    }

    private var subtitle: String {
        if !gateway.enabled {
            return String(localized: "Reçois des messages d'autres apps (Raccourcis, scripts, curl…) et affiche-les sur la matrice.")
        }
        if let error = gateway.lastError { return String(localized: "Erreur : \(error)") }
        let count: String
        switch gateway.receivedCount {
        case 0: count = String(localized: "aucun message reçu")
        case 1: count = String(localized: "1 message reçu")
        default: count = String(localized: "\(gateway.receivedCount) messages reçus")
        }
        return String(localized: "En écoute sur le port \(gateway.port) · \(count)")
    }
}

/// Réglage de la passerelle : port d'écoute + exemples prêts à copier.
private struct GatewaySheet: View {
    @Environment(NotificationGateway.self) var gateway
    @State private var portText = ""
    @FocusState private var portFocused: Bool

    var body: some View {
        SheetScaffold("Passerelle de notifications",
                      subtitle: "N'écoute que sur cet ordinateur (127.0.0.1).",
                      live: true) {
            HStack(spacing: 12) {
                Text("Port d'écoute").foregroundStyle(Theme.textPrimary)
                TextField("8787", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 76)
                    .focused($portFocused)
                    .onSubmit { applyPort() }
                    .onChange(of: portFocused) { _, focused in
                        if !focused { applyPort() }
                    }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                example("Depuis un terminal ou un script :",
                        "curl -X POST http://127.0.0.1:\(gateway.port)/notify -d '{\"text\":\"Coucou\"}'")
                example("Via le schéma d'URL, depuis n'importe où dans macOS :",
                        "open \"lumo://notify?text=Coucou&color=%23FF5555\"")
                example("Dans Raccourcis : action « Obtenir le contenu de l'URL » (méthode POST, corps JSON) vers",
                        "http://127.0.0.1:\(gateway.port)/notify")
            }
        }
        .onAppear { portText = String(gateway.port) }
    }

    private func applyPort() {
        if let value = Int(portText.trimmingCharacters(in: .whitespaces)) {
            gateway.setPort(value)
        }
        portText = String(gateway.port)
    }

    private func example(_ caption: String, _ code: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(caption))
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - Composants partagés

private func cardHeader(_ title: String, icon: String, desc: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Label(LocalizedStringKey(title), systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        Text(LocalizedStringKey(desc)).font(.caption).foregroundStyle(Theme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func optionRow<Trailing: View>(_ title: String, _ desc: String, @ViewBuilder trailing: () -> Trailing) -> some View {
    HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(title)).font(.callout).foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(desc)).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        Spacer()
        trailing()
    }
}

// MARK: - Éditeur de règle

/// Éditeur d'une règle d'alerte.
struct RuleEditor: View {
    let device: Device
    @Environment(AlertsStation.self) var alerts
    @Environment(ConnectorsStation.self) var connectors
    @Environment(\.dismiss) private var dismiss
    @State var rule: AlertRule
    @State private var color: Color

    init(device: Device, rule: AlertRule) {
        self.device = device
        _rule = State(initialValue: rule)
        _color = State(initialValue: Color(hex: rule.colorHex))
    }

    var body: some View {
        SheetScaffold("Règle d'alerte") {
            group("Quand") {
                PillPicker(selection: $rule.trigger, options: [
                    (AlertRule.Trigger.threshold, "Seuil franchi"),
                    (AlertRule.Trigger.schedule, "À heure fixe")
                ])
            }

            if rule.trigger == .threshold {
                group("Condition") {
                    Picker("Surveiller", selection: $rule.metric) {
                        ForEach(AlertRule.Metric.allCases.filter { $0 != .connector || !connectors.connectors.isEmpty }) {
                            Text($0.label).tag($0)
                        }
                    }
                    if rule.metric == .connector {
                        Picker("Connecteur", selection: $rule.connectorID) {
                            Text("Choisir…").tag(UUID?.none)
                            ForEach(connectors.connectors) { c in
                                Text(c.name.isEmpty ? "Sans nom" : c.name).tag(UUID?.some(c.id))
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        PillPicker(selection: $rule.comparison,
                                   options: AlertRule.Comparison.allCases.map { ($0, $0.label) })
                        TextField("Seuil", value: $rule.threshold, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                        Text(rule.metric.unit).foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                group("Horaire") {
                    HStack(spacing: 14) {
                        DatePicker("", selection: scheduleTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        dayTogglesRow
                    }
                    Text("Aucun jour coché = tous les jours.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.8))
                }
            }

            group("Quand ça se déclenche") {
                HStack(spacing: 10) {
                    TextField(rule.trigger == .schedule
                              ? "Message (vide = automatique)"
                              : "Message ({value} = valeur mesurée, vide = automatique)",
                              text: $rule.message)
                        .textFieldStyle(.roundedBorder)
                    ColorPicker("", selection: Binding(
                        get: { color },
                        set: { color = $0; rule.colorHex = $0.hexString }
                    ), supportsOpacity: false).labelsHidden()
                    IconThumbnail(host: device.host, iconID: rule.icon)
                    TextField("Icône", text: $rule.icon).textFieldStyle(.roundedBorder).frame(width: 60)
                }
                HStack(spacing: 10) {
                    TextField("Son (ex. alarm, optionnel)", text: $rule.sound)
                        .textFieldStyle(.roundedBorder).frame(width: 200)
                    Picker("LED témoin", selection: $rule.indicator) {
                        Text("Aucune").tag(0)
                        ForEach(1..<4) { Text("LED \($0)").tag($0) }
                    }
                    .frame(width: 180)
                    Spacer()
                }
                if rule.trigger == .schedule {
                    TextField("App à afficher (ex. weather, optionnel)", text: $rule.switchToApp)
                        .textFieldStyle(.roundedBorder).frame(width: 260)
                    Text("Si une app est renseignée, l'écran bascule dessus au lieu d'afficher la notification.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.8))
                } else {
                    Text("La LED s'allume pendant l'alerte et s'éteint quand la valeur revient à la normale.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.8))
                }
            }

            Divider().overlay(Theme.stroke)
            EditorButtons(
                onDelete: alerts.rules.contains(where: { $0.id == rule.id })
                    ? { alerts.remove(rule); dismiss() } : nil,
                saveDisabled: rule.trigger == .threshold && rule.metric == .connector && rule.connectorID == nil,
                onSave: { save() }
            )
        }
    }

    private func save() {
        if alerts.rules.contains(where: { $0.id == rule.id }) {
            alerts.update(rule)
        } else {
            alerts.add(rule)
        }
        dismiss()
    }

    // MARK: - Planification

    /// Pont Date ↔ minutes depuis minuit pour le DatePicker.
    private var scheduleTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: rule.scheduleMinutes / 60,
                                      minute: rule.scheduleMinutes % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                rule.scheduleMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    /// Rangée compacte L M M J V S D (weekday Calendar : 1=dim…7=sam).
    private var dayTogglesRow: some View {
        HStack(spacing: 5) {
            ForEach(AlertRule.weekOrder, id: \.self) { day in
                dayToggle(day, String(AlertRule.dayShortNames[day - 1].prefix(1)).uppercased())
            }
        }
    }

    private func dayToggle(_ day: Int, _ label: String) -> some View {
        let selected = rule.scheduleDays.contains(day)
        return Button {
            if selected { rule.scheduleDays.remove(day) } else { rule.scheduleDays.insert(day) }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(selected ? Theme.accent : Color.white.opacity(0.08)))
                .foregroundStyle(selected ? Color.black : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .help(AlertRule.dayShortNames[day - 1])
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: String.LocalizationValue(title)).uppercased())
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }
}
