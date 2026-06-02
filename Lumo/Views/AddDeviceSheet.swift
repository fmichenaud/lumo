import SwiftUI

/// Ajout manuel d'un device par IP, avec validation via /api/stats.
struct AddDeviceSheet: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var isChecking = false
    @State private var error: String?
    @State private var notAwtrix = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ajouter un afficheur")
                .font(.title3.weight(.semibold))

            Text("Saisis l'adresse IP de ton AWTRIX (visible dans l'app Ulanzi ou ta box).")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)

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
                Button {
                    Task { await connect() }
                } label: {
                    if isChecking { ProgressView().controlSize(.small) }
                    else { Text("Connecter") }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(host.isEmpty || isChecking)
            }
        }
        .padding(22)
        .frame(width: 420)
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
