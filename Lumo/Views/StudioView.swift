import SwiftUI

/// Section « Studio » : tout ce qui crée du contenu pour la matrice.
/// Deux ateliers — Texte (composition) et Pixel art (dessin) — et une
/// bibliothèque commune « Mes scènes » pour renvoyer une création en 1 clic.
struct StudioView: View {
    let device: Device
    var onResult: (String) -> Void = { _ in }

    @EnvironmentObject var sceneStore: SceneStore
    @AppStorage("studioTab") private var tab = "text"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PillPicker(selection: $tab, options: [
                ("text", String(localized: "Texte")),
                ("pixel", String(localized: "Pixel art"))
            ])

            if tab == "text" {
                ComposeView(device: device, onResult: onResult)
            } else {
                DrawView(device: device, onResult: onResult)
            }

            if !sceneStore.scenes.isEmpty {
                ScenesCard(device: device, onResult: onResult)
            }
        }
    }
}

/// Bibliothèque des scènes sauvegardées : renvoi en 1 clic, suppression.
struct ScenesCard: View {
    let device: Device
    var onResult: (String) -> Void = { _ in }

    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var sceneStore: SceneStore
    @State private var sendingSceneID: UUID?

    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Mes scènes").uppercased())
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)

            ForEach(Array(sceneStore.scenes.enumerated()), id: \.element.id) { index, scene in
                sceneRow(scene)
                if index < sceneStore.scenes.count - 1 {
                    Divider().overlay(Theme.stroke).padding(.vertical, 9)
                }
            }
        }
        .card()
    }

    private func sceneRow(_ scene: DisplayScene) -> some View {
        HStack(spacing: 12) {
            IconThumbnail(host: device.host, iconID: scene.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(scene.name).foregroundStyle(Theme.textPrimary)
                Text(scene.text.isEmpty ? "—" : scene.text)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: scene.colorHex)).frame(width: 14, height: 14)
            Spacer()

            Button { Task { await send(scene) } } label: {
                if sendingSceneID == scene.id { ProgressView().controlSize(.small) }
                else { Label("Envoyer", systemImage: "paperplane.fill") }
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .controlSize(.small)

            Button { sceneStore.remove(scene) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.85))
        }
    }

    private func send(_ scene: DisplayScene) async {
        sendingSceneID = scene.id; defer { sendingSceneID = nil }
        do {
            try await client.upsertCustomApp(name: scene.appName, payload: scene.payload())
            try await client.switchApp(name: scene.appName)
            onResult("Scène « \(scene.name) » envoyée\(scene.persist ? " (persistante)" : "")")
        } catch {
            onResult("Échec de l'envoi")
        }
    }
}
