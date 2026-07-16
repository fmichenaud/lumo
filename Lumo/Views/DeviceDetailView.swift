import SwiftUI

/// Conteneur d'un device : barre « à l'écran » épinglée en haut,
/// puis la section choisie dans la sidebar (Écran, Studio, Moments, Appareil).
struct DeviceDetailView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore

    @State private var banner: String?

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
    }

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
                DeviceSettingsView(device: device, onResult: { banner = $0 })
            }
        }
        .transition(.opacity)
        .id(store.selectedSection)
        .animation(.easeInOut(duration: 0.18), value: store.selectedSection)
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
