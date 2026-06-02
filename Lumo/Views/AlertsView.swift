import SwiftUI

/// Alertes & ambiance : actions ponctuelles indépendantes de la rotation d'apps.
/// Tout est basé sur des actions explicites (pas de toggle à état) pour éviter toute désynchro.
struct AlertsView: View {
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
        .card()
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
