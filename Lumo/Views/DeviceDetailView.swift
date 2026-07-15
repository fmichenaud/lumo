import SwiftUI

/// Tableau de bord d'un device : aperçu live, état, contrôles rapides, composition.
struct DeviceDetailView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore

    @State private var stats: AwtrixStats?
    @State private var brightness: Double = 80
    @State private var autoTransition = true
    @State private var appTime = 5
    @State private var powerOn = true
    @State private var banner: String?
    @State private var moodColor = Theme.accent

    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(spacing: 0) {
            // Zone épinglée (toujours visible) : en-tête + aperçu live.
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                LivePreviewView(host: device.host)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)

            // Contenu de la section, défilant sous l'aperçu.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionIntro
                    sectionContent
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.backgroundGradient)
        .navigationTitle(device.name)
        .overlay(alignment: .top) { bannerView }
        .task(id: device.id) { await refreshState() }
    }

    private var sectionIntro: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.selectedSection.title)
                .font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(store.selectedSection.summary)
                .font(.callout).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cartes

    private var headerCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(device.name)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(stats != nil ? Theme.online : Theme.textSecondary)
                            .frame(width: 7, height: 7)
                        Text(stats != nil ? "Connecté" : "Hors ligne")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .foregroundStyle(Theme.textPrimary)

                    Text(device.host).font(.callout).foregroundStyle(Theme.textSecondary)
                    if let v = stats?.version {
                        Text("· AWTRIX \(v)").font(.callout).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer()
            statChips
        }
    }

    private var statChips: some View {
        HStack(spacing: 10) {
            if let bat = stats?.bat { Chip(icon: "battery.100", text: "\(bat)%") }
            if let t = stats?.temp { Chip(icon: "thermometer.medium", text: "\(Int(t))°") }
            if let h = stats?.hum { Chip(icon: "humidity", text: "\(Int(h))%") }
        }
    }

    @ViewBuilder private var sectionContent: some View {
        Group {
            switch store.selectedSection {
            case .apps:     DeviceAppsView(device: device, onResult: { banner = $0 })
            case .compose:  ComposeView(device: device, onResult: { banner = $0 })
            case .alerts:   AlertsView(device: device, onResult: { banner = $0 })
            case .draw:     DrawView(device: device, onResult: { banner = $0 })
            case .settings: controlsCard
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
            }
            rowDivider

            ControlRow(icon: "arrow.left.arrow.right", title: "Défilement auto",
                       subtitle: "Rotation entre les apps") {
                Toggle("", isOn: Binding(get: { autoTransition }, set: { value in
                    autoTransition = value
                    Task { try? await client.setAutoTransition(value) }
                })).labelsHidden().tint(Theme.accent)
            }
            rowDivider

            ControlRow(icon: "timer", title: "Durée par app",
                       subtitle: "Temps d'affichage avant de passer à la suivante") {
                HStack(spacing: 8) {
                    Text("\(appTime) s")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Stepper("", value: Binding(get: { appTime }, set: { value in
                        appTime = value
                        Task { try? await client.updateSettings(["ATIME": value]) }
                    }), in: 1...60).labelsHidden()
                }
            }

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
            if let t = settings.ATRANS { autoTransition = t }
            if let a = settings.ATIME { appTime = a }
        }
    }
}

private struct Chip: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surfaceHover, in: Capsule())
            .foregroundStyle(Theme.textPrimary)
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
