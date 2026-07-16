import SwiftUI

/// Tableau de bord d'un device : aperçu live, état, contrôles rapides, composition.
struct DeviceDetailView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var nightMode: NightModeStation

    @State private var stats: AwtrixStats?
    @State private var brightness: Double = 80
    @State private var autoBrightness = false
    @State private var powerOn = true
    @State private var banner: String?
    @State private var moodColor = Theme.accent

    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(spacing: 0) {
            // Zone épinglée (toujours visible) : barre « à l'écran » compacte.
            NowPlayingBar(device: device)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 14)

            // Contenu de la section, défilant sous l'aperçu.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.backgroundGradient)
        .navigationTitle(device.name)
        .overlay(alignment: .top) { bannerView }
        .task(id: device.id) { await refreshState() }
    }

    // MARK: - Cartes

    @ViewBuilder private var sectionContent: some View {
        Group {
            switch store.selectedSection {
            case .screen:
                DeviceScreenView(device: device, onResult: { banner = $0 })
            case .studio:
                StudioView(device: device, onResult: { banner = $0 })
            case .moments:
                MomentsView(device: device, onResult: { banner = $0 })
            case .device:
                controlsCard
            }
        }
        .transition(.opacity)
        .id(store.selectedSection)
        .animation(.easeInOut(duration: 0.18), value: store.selectedSection)
    }

    private var brightnessPercent: Int { Int(round(brightness / 255 * 100)) }

    private var controlsCard: some View {
        VStack(spacing: 0) {
            sectionTitle("Contrôles")

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
            rowDivider

            rowDivider
            nightModeBlock

            rowDivider
            sectionTitle("Ambiance")
            Text("Transforme tout l'écran en couleur unie. Masque l'affichage normal tant que c'est allumé.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            HStack(spacing: 12) {
                ColorPicker("Lampe d'ambiance", selection: $moodColor, supportsOpacity: false)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { Task { try? await client.setMoodlight(hex: moodColor.hexString); banner = "Ambiance allumée" } } label: {
                    Label("Allumer", systemImage: "lightbulb.fill")
                }
                .buttonStyle(PillButtonStyle())
                Button { Task { try? await client.moodlightOff(); banner = "Affichage normal restauré" } } label: {
                    Label("Éteindre", systemImage: "lightbulb.slash")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }

        }
        .card()
        .onChange(of: powerOn) { _, value in
            Task { try? await client.setPower(value); banner = value ? "Écran allumé" : "Écran éteint" }
        }
    }

    // MARK: - Mode nuit

    /// Bloc de réglage du mode nuit programmé (branché sur NightModeStation).
    @ViewBuilder private var nightModeBlock: some View {
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

    @ViewBuilder private var bannerView: some View {
        if let banner {
            Text(LocalizedStringKey(banner))
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.surfaceHover, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { self.banner = nil }
                }
        }
    }

    // MARK: - Données

    private func refreshState() async {
        if let s = try? await client.fetchStats() {
            stats = s
            if let b = s.bri { brightness = Double(b) }
        }
        if let settings = try? await client.fetchSettings() {
            if let ab = settings.ABRI { autoBrightness = ab }
        }
    }
}

/// Style de carte réutilisable.
private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// Ligne de réglage homogène : pastille d'icône + titre/sous-titre + contrôle à droite.
struct ControlRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title)).foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle)).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}
