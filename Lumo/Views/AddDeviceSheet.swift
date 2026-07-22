import SwiftUI

/// Ajout manuel d'un device par IP, avec validation via /api/stats.
struct AddDeviceSheet: View {
    @Environment(DeviceStore.self) var store
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var isChecking = false
    @State private var error: String?
    @State private var notAwtrix = false

    var body: some View {
        SheetScaffold("Ajouter un afficheur",
                      subtitle: "Saisis l'adresse IP de ton AWTRIX (visible dans l'app Ulanzi ou ta box).") {
            TextField("192.168.1.41", text: $host)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await connect() } }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if notAwtrix {
                Link(destination: AppInfo.flashGuideURL) {
                    Label("Cet afficheur doit être sous AWTRIX — voir comment l'installer",
                          systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .foregroundStyle(Theme.accent)
            }

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button {
                    Task { await connect() }
                } label: {
                    if isChecking { ProgressView().controlSize(.small) }
                    else { Text("Connecter") }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(host.isEmpty || isChecking)
            }
        }
    }

    private func connect() async {
        error = nil
        notAwtrix = false
        isChecking = true
        defer { isChecking = false }

        let cleaned = host.trimmingCharacters(in: .whitespaces)
        do {
            let stats = try await AwtrixClient(host: cleaned).fetchStats(timeout: 3)
            guard stats.isAwtrix else {
                error = "Cet appareil répond, mais ne semble pas être sous AWTRIX."
                notAwtrix = true
                return
            }
            let uid = stats.uid ?? cleaned
            store.add(Device(id: uid, name: Device.defaultName(for: uid), host: cleaned))
            dismiss()
        } catch {
            self.error = "Aucun appareil joignable à cette adresse."
        }
    }
}
