import SwiftUI

/// Section « Appareil » : le matériel — écran (power, luminosité), mode nuit,
/// lampe d'ambiance, et fiche d'identité du device (IP, version, capteurs).
struct DeviceSettingsView: View {
    let device: Device
    @Environment(DeviceStore.self) var store
    @Environment(NightModeStation.self) var nightMode
    var onResult: (String) -> Void = { _ in }

    @State private var stats: AwtrixStats?
    @State private var brightness: Double = 80
    @State private var autoBrightness = false
    @State private var powerOn = true
    @State private var moodColor = Theme.accent

    private var client: AwtrixClient { store.client(for: device) }
    private var brightnessPercent: Int { Int(round(brightness / 255 * 100)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            screenCard
            nightCard
            moodCard
            infoCard
        }
        .task(id: device.id) { await refresh() }
        .onChange(of: powerOn) { _, value in
            Task { try? await client.setPower(value); onResult(value ? "Écran allumé" : "Écran éteint") }
        }
    }

    // MARK: - Écran

    private var screenCard: some View {
        VStack(spacing: 0) {
            sectionTitle("Écran")

            ControlRow(icon: "power", title: "Écran", subtitle: powerOn ? "Allumé" : "Éteint") {
                Toggle("", isOn: $powerOn).labelsHidden().tint(Theme.accent)
            }
            rowDivider

            ControlRow(icon: "sun.max.fill", title: "Luminosité", subtitle: "\(brightnessPercent) %") {
                Slider(value: $brightness, in: 1...255) { editing in
                    if !editing { Task { try? await client.setBrightness(Int(brightness)) } }
                }
                .tint(Theme.accent)
                .frame(width: 170)
                .disabled(autoBrightness)
            }
            rowDivider

            ControlRow(icon: "circle.lefthalf.filled", title: "Luminosité automatique",
                       subtitle: "Ajuste selon le capteur de lumière ambiante") {
                Toggle("", isOn: Binding(get: { autoBrightness }, set: { value in
                    autoBrightness = value
                    Task { try? await client.updateSettings(["ABRI": value]) }
                })).labelsHidden().tint(Theme.accent)
            }
        }
        .card()
    }

    // MARK: - Mode nuit

    private var nightCard: some View {
        VStack(spacing: 0) {
            sectionTitle("Mode nuit")

            ControlRow(icon: "moon.fill", title: "Mode nuit programmé",
                       subtitle: nightMode.applied ? "Actif en ce moment" : "S'applique automatiquement à l'heure choisie") {
                Toggle("", isOn: Binding(get: { nightMode.enabled }, set: { value in
                    nightMode.setEnabled(value)
                })).labelsHidden().tint(Theme.accent)
            }

            if nightMode.enabled {
                rowDivider

                ControlRow(icon: "clock.fill", title: "Plage horaire",
                           subtitle: "Peut traverser minuit") {
                    HStack(spacing: 8) {
                        DatePicker("", selection: timeBinding(minutes: { nightMode.startMinutes },
                                                              set: { nightMode.setStart(minutes: $0) }),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("→").foregroundStyle(Theme.textSecondary)
                        DatePicker("", selection: timeBinding(minutes: { nightMode.endMinutes },
                                                              set: { nightMode.setEnd(minutes: $0) }),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                rowDivider

                ControlRow(icon: "moon.zzz.fill", title: "Action",
                           subtitle: "Ce qui se passe pendant la nuit") {
                    Picker("", selection: Binding(get: { nightMode.action }, set: { value in
                        nightMode.setAction(value)
                    })) {
                        Text("Éteindre l'écran").tag(NightAction.powerOff)
                        Text("Luminosité réduite").tag(NightAction.dim)
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                if nightMode.action == .dim {
                    rowDivider
                    ControlRow(icon: "sun.min.fill", title: "Luminosité nocturne",
                               subtitle: "\(nightMode.dimPercent) %") {
                        Stepper("", value: Binding(get: { nightMode.dimPercent }, set: { value in
                            nightMode.setDimPercent(value)
                        }), in: 1...100, step: 5).labelsHidden()
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Ambiance

    private var moodCard: some View {
        VStack(spacing: 0) {
            sectionTitle("Lampe d'ambiance")
            Text("Transforme tout l'écran en couleur unie. Masque l'affichage normal tant que c'est allumé.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            HStack(spacing: 12) {
                ColorPicker("Couleur", selection: $moodColor, supportsOpacity: false)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { Task { try? await client.setMoodlight(hex: moodColor.hexString); onResult("Ambiance allumée") } } label: {
                    Label("Allumer", systemImage: "lightbulb.fill")
                }
                .buttonStyle(PillButtonStyle())
                Button { Task { try? await client.moodlightOff(); onResult("Affichage normal restauré") } } label: {
                    Label("Éteindre", systemImage: "lightbulb.slash")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
        .card()
    }

    // MARK: - Infos

    private var infoCard: some View {
        VStack(spacing: 0) {
            sectionTitle("Infos")
            infoRow("network", "Adresse IP", device.host)
            rowDivider
            infoRow("cpu.fill", "Firmware", stats?.version.map { "AWTRIX \($0)" } ?? "—")
            rowDivider
            infoRow("clock.arrow.circlepath", "Allumé depuis", uptimeText)
            rowDivider
            infoRow("battery.100", "Batterie", stats?.bat.map { "≈ \($0) %" } ?? "—")
                .help("Estimation par la tension de la batterie — peu précise, et faussée quand l'appareil est branché en USB (la charge n'est pas détectable sur le TC001).")
            rowDivider
            infoRow("thermometer.medium", "Température", stats?.temp.map { "\(Int($0)) °C" } ?? "—")
            rowDivider
            infoRow("humidity", "Humidité", stats?.hum.map { "\(Int($0)) %" } ?? "—")
            rowDivider
            infoRow("wifi", "Signal Wi-Fi", stats?.wifiSignal.map { "\($0) dBm" } ?? "—")

            Text("Batterie : estimation d'après la tension, peu précise — et surestimée quand l'appareil est branché en USB. Le TC001 ne sait pas détecter la charge.")
                .font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        }
        .card()
    }

    private func infoRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22)
            Text(LocalizedStringKey(title)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
        }
    }

    private var uptimeText: String {
        guard let s = stats?.uptime else { return "—" }
        let h = s / 3600, m = (s % 3600) / 60
        if h >= 24 { return String(localized: "\(h / 24) j \(h % 24) h") }
        if h > 0 { return String(localized: "\(h) h \(m) min") }
        return String(localized: "\(m) min")
    }

    // MARK: - Helpers

    /// Binding Date ↔︎ minutes depuis minuit pour les DatePicker heure/minute.
    private func timeBinding(minutes: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding<Date>(
            get: {
                let m = minutes()
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
            }
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(String(localized: String.LocalizationValue(text)).uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
    }

    private var rowDivider: some View {
        Divider().overlay(Theme.stroke).padding(.vertical, 12)
    }

    // MARK: - Données

    private func refresh() async {
        stats = try? await client.fetchStats()
        if let b = stats?.bri { brightness = Double(b) }
        if let settings = try? await client.fetchSettings() {
            if let ab = settings.ABRI { autoBrightness = ab }
        }
    }
}
