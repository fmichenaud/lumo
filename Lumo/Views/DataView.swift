import SwiftUI

/// Section Données : des apps "vivantes" qu'on branche sur l'afficheur et que Lumo met à jour tout seul.
struct DataView: View {
    let device: Device
    @EnvironmentObject var live: LiveAppsStation

    var body: some View {
        VStack(spacing: 16) {
            liveRow(
                icon: "cpu", title: "CPU du Mac",
                subtitle: "Charge processeur · mise à jour toutes les 5 s",
                value: "\(live.cpuValue)%",
                isOn: live.cpuOn, set: { live.setCPU($0) }
            )
            Divider().overlay(Theme.stroke)
            liveRow(
                icon: "memorychip", title: "RAM du Mac",
                subtitle: "Mémoire utilisée · mise à jour toutes les 5 s",
                value: "\(live.ramValue)%",
                isOn: live.ramOn, set: { live.setRAM($0) }
            )
            Divider().overlay(Theme.stroke)
            cryptoRow
        }
        .card()
    }

    private func liveRow(icon: String, title: String, subtitle: String, value: String,
                         isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(0.14)).frame(width: 34, height: 34)
                Image(systemName: icon).foregroundStyle(Theme.accent).font(.system(size: 15, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if isOn {
                Text(value).font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            Toggle("", isOn: Binding(get: { isOn }, set: set)).labelsHidden().tint(Theme.accent)
        }
    }

    private var cryptoRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(0.14)).frame(width: 34, height: 34)
                    Image(systemName: "bitcoinsign").foregroundStyle(Theme.accent).font(.system(size: 15, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Crypto").foregroundStyle(Theme.textPrimary)
                    Text("Cours en direct · mise à jour toutes les 60 s").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if live.cryptoOn, let p = live.cryptoPrice {
                    Text("\(format(p))\(live.currencySymbol)")
                        .font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                }
                Toggle("", isOn: Binding(get: { live.cryptoOn }, set: { live.setCrypto($0) }))
                    .labelsHidden().tint(Theme.accent)
            }
            HStack(spacing: 10) {
                Picker("", selection: Binding(get: { live.coinID }, set: { live.setCoin($0) })) {
                    ForEach(DataService.coins) { Text($0.symbol).tag($0.id) }
                }
                .frame(width: 110)
                Picker("", selection: Binding(get: { live.currency }, set: { live.setCurrency($0) })) {
                    Text("EUR").tag("eur"); Text("USD").tag("usd")
                }
                .frame(width: 90)
                Spacer()
            }
            .padding(.leading, 46)
        }
    }

    private func format(_ p: Double) -> String {
        p >= 100 ? String(Int(p.rounded())) : String(format: "%.2f", p)
    }
}
