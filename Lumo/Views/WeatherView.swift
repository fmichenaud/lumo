import SwiftUI

/// Sheet de configuration de l'intégration Météo : choix de la ville, aperçu, envoi manuel.
/// L'état (ville, météo, auto) est porté par WeatherStation, partagé avec la menu-bar.
struct WeatherConfigSheet: View {
    let device: Device
    @Environment(DeviceStore.self) var store
    @Environment(WeatherStation.self) var weatherStation
    @Environment(\.dismiss) private var dismiss
    var onResult: (String) -> Void = { _ in }

    @State private var query = ""
    @State private var results: [GeoPlace] = []
    @State private var busy = false
    @State private var sending = false

    var body: some View {
        SheetScaffold("Météo",
                      subtitle: "Choisis ta ville — l'afficheur se met à jour toutes les 15 min quand l'app est activée.",
                      height: 380,
                      live: true,
                      content: {
            VStack(alignment: .leading, spacing: 0) {
                searchBar
                if !results.isEmpty { resultsList }
                if weatherStation.hasLocation { currentBlock }
                Spacer(minLength: 0)
            }
        }, accessory: {
            if busy { ProgressView().controlSize(.small) }
        })
        .task { if weatherStation.hasLocation && weatherStation.weather == nil { await weatherStation.refresh() } }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Ville (Paris, Lyon, Bordeaux…)", text: $query)
                .textFieldStyle(.plain)
                .onSubmit { Task { await search() } }
            if !query.isEmpty {
                Button { Task { await search() } } label: { Text("Chercher") }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .controlSize(.small)
            }
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
    }

    private var resultsList: some View {
        VStack(spacing: 2) {
            ForEach(results) { place in
                Button { pick(place) } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.accent)
                        Text(place.label).foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }

    private var currentBlock: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                IconThumbnail(host: device.host, iconID: weatherStation.weather?.condition.iconID ?? "")
                    .scaleEffect(1.4)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(weatherStation.locationLabel).font(.callout.weight(.medium))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(weatherStation.weather?.condition.label ?? "—")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(weatherStation.weather?.tempText ?? "—")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(spacing: 12) {
                Button { Task { busy = true; await weatherStation.refresh(); busy = false } } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle(prominent: false))

                Button { Task { await send() } } label: {
                    if sending { ProgressView().controlSize(.small) }
                    else { Label("Envoyer sur l'afficheur", systemImage: "paperplane.fill") }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(weatherStation.weather == nil || sending)

                Spacer()
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Actions

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        busy = true; defer { busy = false }
        results = (try? await WeatherService.geocode(query)) ?? []
        if results.isEmpty { onResult("Aucune ville trouvée") }
    }

    private func pick(_ place: GeoPlace) {
        weatherStation.setLocation(place)
        results = []
        query = ""
    }

    private func send() async {
        sending = true; defer { sending = false }
        await weatherStation.push(switchTo: true)
        if let w = weatherStation.weather {
            onResult("Météo envoyée : \(w.tempText) · \(w.condition.label)")
        }
    }
}
