import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Galerie d'icônes intégrée : recherche LaMetric en direct, clic = envoi sur l'afficheur.
/// Les icônes animées sont uploadées telles quelles (GIF 8×8) ; les statiques sont converties.
struct IconImportSheet: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    let device: Device
    var onImported: (String) -> Void

    @State private var searchText = ""
    @State private var icons: [LaMetricIcon] = []
    @State private var loading = false
    @State private var importingID: Int?
    @State private var status: String?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 12)]

    var body: some View {
        SheetScaffold("Galerie d'icônes",
                      subtitle: "Cherche, clique : l'icône part directement sur l'afficheur.",
                      width: 600, height: 560,
                      content: {
            searchBar
            content
            if let status {
                Text(status).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }, accessory: {
            Button { chooseFile() } label: { Label("Fichier…", systemImage: "folder") }
                .buttonStyle(PillButtonStyle(prominent: false))
        })
        .task { await runSearch() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Rechercher (trophy, clock, heart, fire…)", text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, _ in debouncedSearch() }
            if loading { ProgressView().controlSize(.small) }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
    }

    @ViewBuilder private var content: some View {
        if loading && icons.isEmpty {
            Spacer(); ProgressView().controlSize(.large); Spacer()
        } else if icons.isEmpty {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.title)
                Text("Aucune icône trouvée").font(.callout)
            }
            .foregroundStyle(Theme.textSecondary)
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(icons) { cell($0) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func cell(_ icon: LaMetricIcon) -> some View {
        Button { Task { await importIcon(icon) } } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.matrixBackground)
                    AsyncImage(url: icon.assetURL) { phase in
                        if let image = phase.image {
                            image.interpolation(.none).resizable().scaledToFit().padding(12)
                        } else if phase.error != nil {
                            Image(systemName: "questionmark").foregroundStyle(Theme.textSecondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if icon.isAnimated {
                        Image(systemName: "play.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    if importingID == icon.id {
                        RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.55))
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 76)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
                Text(icon.name).font(.caption2).lineLimit(1)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .help(icon.isAnimated ? "\(icon.name) · animée" : icon.name)
    }

    // MARK: - Recherche

    private func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        loading = true; defer { loading = false }
        do {
            let results = try await LaMetricService.search(term: searchText)
            icons = results
            status = results.isEmpty ? nil : "\(results.count) icônes · clique pour envoyer"
        } catch {
            status = "Recherche indisponible (vérifie ta connexion)."
        }
    }

    // MARK: - Import

    private func importIcon(_ icon: LaMetricIcon) async {
        importingID = icon.id; defer { importingID = nil }
        do {
            let data = try await LaMetricService.fetchIcon(id: String(icon.id))
            let gif = try resolveGIF(from: data)
            try await store.client(for: device).uploadIcon(id: String(icon.id), data: gif, ext: "gif")
            onImported(String(icon.id))
            dismiss()
        } catch {
            status = "Échec de l'import de « \(icon.name) »."
        }
    }

    /// GIF animé déjà en 8×8 → conservé tel quel ; sinon conversion (PNG → GIF sur fond noir).
    private func resolveGIF(from data: Data) throws -> Data {
        let isGIF = data.starts(with: [0x47, 0x49, 0x46]) // "GIF"
        if isGIF { return data }
        guard let result = IconConverter.makeAwtrixIcon(from: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return result.gif
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .bmp, .image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        Task {
            importingID = -1; defer { importingID = nil }
            do {
                let gif = try resolveGIF(from: data)
                try await store.client(for: device).uploadIcon(id: name, data: gif, ext: "gif")
                onImported(name)
                dismiss()
            } catch {
                status = "Échec de l'import du fichier."
            }
        }
    }
}
