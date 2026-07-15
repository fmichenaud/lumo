import SwiftUI

/// Alertes programmables : des règles à seuil (CPU, batterie, connecteur…) qui déclenchent
/// automatiquement une notification et/ou une LED témoin. Les actions manuelles
/// (notification ponctuelle, LED) restent disponibles, repliées en bas.
struct AlertsView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var alerts: AlertsStation
    @EnvironmentObject var connectors: ConnectorsStation
    var onResult: (String) -> Void = { _ in }

    @State private var editing: AlertRule?
    @State private var showManual = false

    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            rulesBlock
            Divider().overlay(Theme.stroke)
            DisclosureGroup(isExpanded: $showManual) {
                ManualActionsView(device: device, onResult: onResult)
                    .padding(.top, 12)
            } label: {
                Label("Actions manuelles (notification ponctuelle, LED)", systemImage: "hand.tap.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
        .sheet(item: $editing) { rule in
            RuleEditor(device: device, rule: rule)
                .environmentObject(alerts)
                .environmentObject(connectors)
        }
    }

    // MARK: - Règles

    private var rulesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Règles d'alerte").uppercased())
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Theme.textSecondary)

            if alerts.rules.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill").font(.title2)
                    Text("Aucune règle").font(.callout)
                    Text("Exemple : « si le CPU du Mac dépasse 90 %, affiche une alerte rouge ».")
                        .font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(alerts.rules) { ruleRow($0) }
            }

            Button { editing = AlertRule() } label: {
                Label("Ajouter une règle", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
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
                if rule.trigger == .schedule {
                    Text(LocalizedStringKey(rule.enabled ? "Planifiée" : "Inactive"))
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                } else if isActive {
                    Text("Alerte en cours").font(.caption2).foregroundStyle(.red)
                } else if let v = alerts.lastValues[rule.id] {
                    Text("Actuellement : \(AlertRule.format(v))\(rule.metric.unit)")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                } else {
                    Text(LocalizedStringKey(rule.enabled ? "En attente de données…" : "Inactive"))
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

/// Éditeur d'une règle d'alerte.
private struct RuleEditor: View {
    let device: Device
    @EnvironmentObject var alerts: AlertsStation
    @EnvironmentObject var connectors: ConnectorsStation
    @Environment(\.dismiss) private var dismiss
    @State var rule: AlertRule
    @State private var color: Color

    init(device: Device, rule: AlertRule) {
        self.device = device
        _rule = State(initialValue: rule)
        _color = State(initialValue: Color(hex: rule.colorHex))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Règle d'alerte").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)

            group("Quand") {
                Picker("", selection: $rule.trigger) {
                    Text("Seuil franchi").tag(AlertRule.Trigger.threshold)
                    Text("À heure fixe").tag(AlertRule.Trigger.schedule)
                }
                .pickerStyle(.segmented).labelsHidden()
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
                        Picker("", selection: $rule.comparison) {
                            ForEach(AlertRule.Comparison.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).frame(width: 220)
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
            HStack(spacing: 10) {
                if alerts.rules.contains(where: { $0.id == rule.id }) {
                    Button(role: .destructive) { alerts.remove(rule); dismiss() } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.plain).foregroundStyle(.red)
                }
                Spacer()
                Button("Annuler") { dismiss() }.buttonStyle(PillButtonStyle(prominent: false))
                Button("Enregistrer") { save() }.buttonStyle(PillButtonStyle())
                    .disabled(rule.trigger == .threshold && rule.metric == .connector && rule.connectorID == nil)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.background)
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

/// Actions ponctuelles : notification manuelle et LED témoins (ancien contenu de la section).
private struct ManualActionsView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore
    var onResult: (String) -> Void = { _ in }

    // Notification
    @State private var text = ""
    @State private var color = Theme.accent
    @State private var icon = ""
    @State private var effect = ""
    @State private var sound = ""
    @State private var hold = false
    @State private var wakeup = true
    @State private var effects: [String] = []
    @State private var showAdvanced = false

    // Indicateurs
    @State private var indicatorColors: [Color] = [.red, .green, Theme.accent]

    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(spacing: 22) {
            notificationBlock
            Divider().overlay(Theme.stroke)
            indicatorsBlock
        }
        .task { effects = (try? await client.fetchEffects()) ?? [] }
    }

    // MARK: - Notification

    private var notificationBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            blockHeader("Notification", icon: "bell.badge.fill",
                        desc: "Affiche un message par-dessus l'écran quelques secondes, puis disparaît. Pour une alerte ponctuelle.")
            HStack(spacing: 10) {
                TextField("Message à afficher", text: $text).textFieldStyle(.roundedBorder)
                ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
                IconThumbnail(host: device.host, iconID: icon)
                TextField("Icône", text: $icon).textFieldStyle(.roundedBorder).frame(width: 60)
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

            Button { Task { await sendNotification() } } label: {
                Label("Envoyer la notification", systemImage: "paperplane.fill")
            }
            .buttonStyle(PillButtonStyle())
            .disabled(text.isEmpty && icon.isEmpty)
        }
    }

    // MARK: - Indicateurs

    private var indicatorsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            blockHeader("Indicateurs LED", icon: "circle.lefthalf.filled",
                        desc: "Les 3 petites LED sur le bord de l'écran. Pratiques comme témoins de statut (ex. rouge = alerte).")
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 12) {
                    ColorPicker("", selection: $indicatorColors[i], supportsOpacity: false).labelsHidden()
                    Text("Indicateur \(i + 1)").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Allumer") { Task { try? await client.setIndicator(i + 1, rgb: indicatorColors[i].rgbArray); onResult("Indicateur \(i + 1) allumé") } }
                        .buttonStyle(PillButtonStyle(prominent: false)).controlSize(.small)
                    Button("Éteindre") { Task { try? await client.clearIndicator(i + 1); onResult("Indicateur \(i + 1) éteint") } }
                        .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Composants

    private func blockHeader(_ title: String, icon: String, desc: String) -> some View {
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

    // MARK: - Actions

    private func sendNotification() async {
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
