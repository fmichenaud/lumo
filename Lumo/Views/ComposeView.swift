import SwiftUI

/// Compose un message et l'envoie au device : soit en notification éphémère,
/// soit épinglé comme app permanente dans la rotation.
struct ComposeView: View {
    let device: Device
    var onResult: (String) -> Void = { _ in }

    @EnvironmentObject var store: DeviceStore

    @State private var text = "1012"
    @State private var color = Theme.accent
    @State private var iconID = ""
    @State private var appName = "lumo"
    @State private var sending = false
    @State private var showIconImport = false
    @State private var saveApp = true

    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Composer un affichage", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Texte").font(.caption).foregroundStyle(Theme.textSecondary)
                    TextField("Ton message", text: $text)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couleur").font(.caption).foregroundStyle(Theme.textSecondary)
                    ColorPicker("", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Icône").font(.caption).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        IconThumbnail(host: device.host, iconID: iconID)
                        TextField("ID", text: $iconID)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                        Button { showIconImport = true } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .help("Parcourir la galerie / importer une icône")
                    }
                }
            }

            // Mini aperçu de la couleur choisie
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 22, height: 22)
                Text(color.hexString).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            Divider().overlay(Theme.stroke)

            HStack(spacing: 12) {
                TextField("Nom de l'app", text: $appName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Toggle(isOn: $saveApp) { Text("Garder après reboot").font(.caption) }
                    .help("Sauvegarde l'app dans la mémoire du device pour qu'elle survive au redémarrage")

                Spacer()

                Button {
                    Task { await addApp() }
                } label: {
                    if sending { ProgressView().controlSize(.small) }
                    else { Label("Ajouter à l'affichage", systemImage: "plus.rectangle.on.rectangle") }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(text.isEmpty && iconID.isEmpty)
            }
        }
        .card()
        .sheet(isPresented: $showIconImport) {
            IconImportSheet(device: device) { importedName in
                iconID = importedName
            }
            .environmentObject(store)
        }
    }

    private func payload() -> PushPayload {
        var p = PushPayload()
        p.text = text.isEmpty ? nil : text
        p.color = color.hexString
        let icon = iconID.trimmingCharacters(in: .whitespaces)
        if !icon.isEmpty { p.icon = icon }
        p.save = saveApp
        p.repeatCount = 1   // défile le texte en entier avant de passer à l'app suivante
        return p
    }

    private func addApp() async {
        sending = true
        defer { sending = false }
        let name = appName.isEmpty ? "lumo" : appName
        do {
            try await client.upsertCustomApp(name: name, payload: payload())
            try await client.switchApp(name: name)
            onResult("« \(name) » ajouté à l'affichage\(saveApp ? " (permanent)" : "")")
        } catch {
            onResult("Échec de l'ajout")
        }
    }
}

/// Vignette de l'icône courante : l'image réelle de l'afficheur, repli sur LaMetric, sinon placeholder.
struct IconThumbnail: View {
    let host: String
    let iconID: String

    private var deviceURL: URL? {
        guard !iconID.isEmpty else { return nil }
        return URL(string: "http://\(host)/ICONS/\(iconID).gif")
    }
    private var laMetricURL: URL? {
        let trimmed = iconID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://developer.lametric.com/content/apps/icon_thumbs/\(trimmed)")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Theme.matrixBackground)
            if iconID.trimmingCharacters(in: .whitespaces).isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            } else {
                AsyncImage(url: deviceURL) { phase in
                    if let image = phase.image {
                        image.interpolation(.none).resizable().scaledToFit().padding(4)
                    } else if phase.error != nil {
                        fallback
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .id(iconID)
            }
        }
        .frame(width: 34, height: 34)
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.stroke))
    }

    @ViewBuilder private var fallback: some View {
        AsyncImage(url: laMetricURL) { phase in
            if let image = phase.image {
                image.interpolation(.none).resizable().scaledToFit().padding(4)
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
        }
    }
}
