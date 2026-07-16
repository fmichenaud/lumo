import SwiftUI

/// Barre « à l'écran en ce moment » : identité du device, mini-matrice live,
/// app courante et statut sur une seule ligne compacte (~64 pt). Un clic sur le
/// chevron (ou la mini-matrice) déploie l'aperçu en grand. Remplace l'ancien
/// couple en-tête + grande carte d'aperçu qui consommait ~40 % de la fenêtre.
struct NowPlayingBar: View {
    let device: Device

    @StateObject private var screen = ScreenStreamer()
    @AppStorage("nowPlayingExpanded") private var expanded = false
    @State private var stats: AwtrixStats?

    private var client: AwtrixClient { AwtrixClient(host: device.host) }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                miniMatrix
                identity
                Spacer()
                expandButton
            }
            if expanded {
                MatrixPreviewView(pixels: screen.pixels)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card()
        .task(id: device.id) {
            screen.start(host: device.host)
            while !Task.isCancelled {
                stats = try? await client.fetchStats()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .onDisappear { screen.stop() }
    }

    // MARK: - Composants

    private var miniMatrix: some View {
        MatrixPreviewView(pixels: screen.pixels)
            .frame(width: 176, height: 44)
            .contentShape(Rectangle())
            .onTapGesture { toggleExpanded() }
            .help(expanded ? "Réduire l'aperçu" : "Agrandir l'aperçu")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(device.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 5) {
                    Circle().fill(screen.isLive ? Theme.online : Theme.textSecondary)
                        .frame(width: 6, height: 6)
                    Text(screen.isLive ? "Connecté" : "Hors ligne")
                        .font(.caption2.weight(.medium))
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: Capsule())
                .foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 6) {
                if let app = stats?.app, !app.isEmpty {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption2).foregroundStyle(Theme.accent)
                    Text("À l'écran : \(app.capitalized)")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                } else {
                    Text(device.host).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var expandButton: some View {
        Button { toggleExpanded() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.05), in: Circle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "Réduire l'aperçu" : "Agrandir l'aperçu")
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded.toggle() }
    }
}
