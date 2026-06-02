import SwiftUI

/// Contenu de la menu-bar : aperçu rapide et actions sans ouvrir la fenêtre.
struct MenuBarView: View {
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var weatherStation: WeatherStation
    @Environment(\.openWindow) private var openWindow

    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            weatherBlock
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 290)
    }

    private var header: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.accentGradient)
                .frame(width: 24, height: 24)
                .overlay(Image(systemName: "rays").font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.8)))
            VStack(alignment: .leading, spacing: 1) {
                Text(store.selectedDevice?.name ?? "Aucun afficheur")
                    .font(.callout.weight(.semibold))
                if let host = store.selectedDevice?.host {
                    Text(host).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var weatherBlock: some View {
        if let weather = weatherStation.weather {
            HStack(spacing: 12) {
                if let device = store.selectedDevice {
                    IconThumbnail(host: device.host, iconID: weather.condition.iconID)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(weatherStation.locationLabel).font(.caption).lineLimit(1)
                    Text(weather.condition.label).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(weather.tempText).font(.title3.weight(.semibold).monospacedDigit())
            }
        } else {
            Text("Météo non configurée").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if weatherStation.weather != nil && store.selectedDevice != nil {
                Button {
                    sending = true
                    Task { await weatherStation.push(switchTo: true); sending = false }
                } label: {
                    HStack {
                        Label("Envoyer la météo", systemImage: "paperplane.fill")
                        Spacer()
                        if sending { ProgressView().controlSize(.small) }
                    }
                    .frame(maxWidth: .infinity)
                }

                Toggle(isOn: Binding(
                    get: { weatherStation.autoEnabled },
                    set: { weatherStation.setAuto($0) }
                )) {
                    Label("Mise à jour auto (15 min)", systemImage: "clock.arrow.2.circlepath")
                }
            }

            Divider().padding(.vertical, 2)

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Ouvrir Lumo", systemImage: "macwindow").frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quitter", systemImage: "power").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
