import SwiftUI

/// Bibliothèque de scènes : compositions sauvegardées, renvoyables en 1 clic (persistance reboot).
struct ScenesView: View {
    let device: Device
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var sceneStore: SceneStore
    var onResult: (String) -> Void = { _ in }

    @State private var name = ""
    @State private var text = ""
    @State private var color = Theme.accent
    @State private var icon = ""
    @State private var sendingID: UUID?

    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(spacing: 18) {
            creator
            if !sceneStore.scenes.isEmpty {
                Divider().overlay(Theme.stroke)
                list
            }
        }
        .card()
    }

    private var creator: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOUVELLE SCÈNE")
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                TextField("Nom (ex. Compteurs)", text: $name)
                    .textFieldStyle(.roundedBorder).frame(width: 150)
                TextField("Texte", text: $text)
                    .textFieldStyle(.roundedBorder)
                ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden()
                IconThumbnail(host: device.host, iconID: icon)
                TextField("Icône", text: $icon)
                    .textFieldStyle(.roundedBorder).frame(width: 64)
            }

            Button {
                let scene = DisplayScene(name: name.isEmpty ? "Scène" : name,
                                  text: text, colorHex: color.hexString, icon: icon)
                sceneStore.add(scene)
                name = ""; text = ""; icon = ""
                onResult("Scène enregistrée")
            } label: {
                Label("Enregistrer la scène", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .disabled(text.isEmpty && icon.isEmpty)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            Text("MES SCÈNES")
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)

            ForEach(Array(sceneStore.scenes.enumerated()), id: \.element.id) { index, scene in
                row(scene)
                if index < sceneStore.scenes.count - 1 {
                    Divider().overlay(Theme.stroke).padding(.vertical, 9)
                }
            }
        }
    }

    private func row(_ scene: DisplayScene) -> some View {
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
                if sendingID == scene.id { ProgressView().controlSize(.small) }
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
        sendingID = scene.id; defer { sendingID = nil }
        do {
            try await client.upsertCustomApp(name: scene.appName, payload: scene.payload())
            try await client.switchApp(name: scene.appName)
            onResult("Scène « \(scene.name) » envoyée\(scene.persist ? " (persistante)" : "")")
        } catch {
            onResult("Échec de l'envoi")
        }
    }
}
