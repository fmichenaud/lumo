import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: DeviceStore
    @StateObject private var discovery = DeviceDiscovery()

    var body: some View {
        NavigationSplitView {
            SidebarView(discovery: discovery, onScan: runScan)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            if let device = store.selectedDevice {
                DeviceDetailView(device: device)
                    .id(device.id)
            } else {
                OnboardingView(discovery: discovery, onScan: runScan)
            }
        }
        .background(Theme.backgroundGradient)
        .toggleStyle(ModernToggleStyle())
        .task {
            // Découverte automatique au lancement si aucun device connu :
            // le prompt macOS « réseau local » arrive dans un contexte naturel.
            if store.devices.isEmpty { runScan() }
        }
    }

    /// Lance la découverte, en réessayant si rien n'est trouvé
    /// (cas typique : l'autorisation réseau vient juste d'être accordée).
    private func runScan() {
        Task {
            for attempt in 0..<3 {
                let found = await discovery.scan()
                store.merge(discovered: found)
                if !found.isEmpty { break }
                if attempt < 2 { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            }
        }
    }
}

/// Écran d'accueil quand aucun device n'est connu : auto-recherche guidée + ajout manuel.
struct OnboardingView: View {
    @ObservedObject var discovery: DeviceDiscovery
    var onScan: () -> Void
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 92, height: 92)
                Image(systemName: discovery.isScanning ? "dot.radiowaves.left.and.right" : "display")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor, isActive: discovery.isScanning)
            }

            if discovery.isScanning {
                Text("Recherche de ton afficheur…")
                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("Si macOS demande l'accès au réseau local, autorise-le :\nla recherche reprend toute seule.")
                    .multilineTextAlignment(.center)
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                ProgressView(value: discovery.progress)
                    .tint(Theme.accent)
                    .frame(width: 240)
            } else {
                Text("Bienvenue dans Lumo")
                    .font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text("Branche ton afficheur AWTRIX sur le même réseau,\nLumo le trouve automatiquement.")
                    .multilineTextAlignment(.center)
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    Button(action: onScan) {
                        Label("Rechercher", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(PillButtonStyle())
                    Button("Ajouter par IP") { showAddSheet = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
                Link(destination: AppInfo.flashGuideURL) {
                    Text("Ton afficheur n'apparaît pas ? Il doit être sous AWTRIX — guide d'installation")
                        .font(.caption)
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient)
        .sheet(isPresented: $showAddSheet) { AddDeviceSheet() }
    }
}
