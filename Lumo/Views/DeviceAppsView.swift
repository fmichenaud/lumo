import SwiftUI

/// Centre de contrôle de la rotation, en direct :
/// - apps "togglables" (live CPU/RAM/Crypto + natives Heure/Date…) : activer/désactiver, réversible
/// - autres apps présentes (Affichage, Dessin, scènes…) : afficher / supprimer
struct DeviceAppsView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var live: LiveAppsStation
    @EnvironmentObject var connectors: ConnectorsStation
    var onResult: (String) -> Void = { _ in }

    @State private var loopApps: [LoopApp] = []
    @State private var current: String?
    @State private var nativeOn: [String: Bool] = [:]

    private var client: AwtrixClient { store.client(for: device) }

    struct LoopApp: Identifiable { let name: String; let position: Int; var id: String { name } }

    // Apps natives : (clé réglage, nom dans la loop, titre, icône)
    private let natives: [(key: String, loop: String, title: String, icon: String)] = [
        ("TIM", "Time", "Heure", "clock.fill"),
        ("DAT", "Date", "Date", "calendar"),
        ("TEMP", "Temperature", "Température", "thermometer.medium"),
        ("HUM", "Humidity", "Humidité", "humidity.fill"),
        ("BAT", "Battery", "Batterie", "battery.100")
    ]
    private let managedNames: Set<String> = ["cpu", "ram", "crypto", "time", "date", "temperature", "humidity", "battery", "notification"]

    var body: some View {
        VStack(spacing: 14) {
            header

            groupLabel("Données")
            toggleRow(icon: "cpu", title: "CPU du Mac", loopName: "cpu", section: .data,
                      isOn: live.cpuOn) { live.setCPU($0) }
            toggleRow(icon: "memorychip", title: "RAM du Mac", loopName: "ram", section: .data,
                      isOn: live.ramOn) { live.setRAM($0) }
            toggleRow(icon: "bitcoinsign", title: "Crypto", loopName: "crypto", section: .data,
                      isOn: live.cryptoOn) { live.setCrypto($0) }

            if !connectors.connectors.isEmpty {
                groupLabel("Intégrations")
                ForEach(connectors.connectors) { c in
                    toggleRow(icon: "antenna.radiowaves.left.and.right",
                              title: c.name.isEmpty ? "Connecteur" : c.name,
                              loopName: c.appName, section: .integrations,
                              isOn: c.enabled) { connectors.setEnabled(c, $0) }
                }
            }

            groupLabel("Système")
            ForEach(natives, id: \.key) { n in
                toggleRow(icon: n.icon, title: n.title, loopName: n.loop, section: .settings,
                          isOn: nativeOn[n.key] ?? false) { setNative(n.key, $0) }
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
            Text("CENTRE DE CONTRÔLE")
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(Theme.online).frame(width: 6, height: 6)
                Text("en direct").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Apps présentes dans la loop qui ne sont pas des apps gérées (live/natives) ni transitoires.
    private var otherApps: [LoopApp] {
        let connectorNames = Set(connectors.connectors.map { $0.appName.lowercased() })
        return loopApps.filter {
            !managedNames.contains($0.name.lowercased()) && !connectorNames.contains($0.name.lowercased())
        }
    }

    // MARK: - Lignes

    private func toggleRow(icon: String, title: String, loopName: String,
                           section: DeviceSection, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        let isCurrent = current?.lowercased() == loopName.lowercased()
        return HStack(spacing: 12) {
            Button { store.selectedSection = section } label: {
                HStack(spacing: 12) {
                    iconBadge(icon, active: isCurrent)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(title)).foregroundStyle(Theme.textPrimary)
                            if isCurrent {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.caption2).foregroundStyle(Theme.accent)
                            }
                        }
                        Text(LocalizedStringKey(isCurrent ? "À l'écran maintenant" : (isOn ? "Active" : "Inactive")))
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    private func setNative(_ key: String, _ on: Bool) {
        nativeOn[key] = on
        Task { try? await client.updateSettings([key: on]) }
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
