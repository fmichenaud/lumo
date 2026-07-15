import SwiftUI

/// Sheet du minuteur : durées rapides ou custom, mode Pomodoro, message de fin,
/// temps restant en grand et bouton Démarrer/Arrêter.
struct PomodoroSheet: View {
    @EnvironmentObject var pomodoro: PomodoroStation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold("Minuteur",
                      subtitle: "Compte à rebours affiché sur la matrice, sonnerie à zéro.",
                      live: true) {
            // Temps restant en grand quand le minuteur est actif.
            if pomodoro.isActive {
                VStack(spacing: 4) {
                    Text(PomodoroStation.timeText(Int(pomodoro.remaining.rounded())))
                        .font(.system(size: 46, weight: .bold).monospacedDigit())
                        .foregroundStyle(pomodoro.isRunning ? Theme.textPrimary : Theme.textSecondary)
                    if pomodoro.pomodoroMode {
                        Text(pomodoro.onBreak
                             ? "Pause · cycle \(pomodoro.cycleCount) terminé"
                             : "Travail · cycle \(pomodoro.cycleCount + 1)")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    } else if !pomodoro.isRunning {
                        Text("En pause").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Choix de la durée (désactivé pendant le décompte et en mode Pomodoro).
            HStack(spacing: 8) {
                ForEach(PomodoroStation.presets, id: \.self) { m in
                    Button("\(m) min") { pomodoro.setMinutes(m) }
                        .buttonStyle(PillButtonStyle(prominent: pomodoro.customMinutes == m))
                        .controlSize(.small)
                }
                Spacer()
                Stepper(value: Binding(get: { pomodoro.customMinutes },
                                       set: { pomodoro.setMinutes($0) }), in: 1...180) {
                    Text("\(pomodoro.customMinutes) min")
                        .font(.callout.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                }
            }
            .disabled(pomodoro.isActive || pomodoro.pomodoroMode)
            .opacity(pomodoro.isActive || pomodoro.pomodoroMode ? 0.5 : 1)

            Toggle(isOn: Binding(get: { pomodoro.pomodoroMode },
                                 set: { pomodoro.setPomodoroMode($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mode Pomodoro").foregroundStyle(Theme.textPrimary)
                    Text("Travail 25 min et pause 5 min, enchaînés.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            .toggleStyle(.switch).tint(Theme.accent)
            .disabled(pomodoro.isActive)

            TextField("Message de fin", text: Binding(get: { pomodoro.endMessage },
                                                      set: { pomodoro.setEndMessage($0) }))
                .textFieldStyle(.roundedBorder)

            if pomodoro.isActive {
                Button {
                    pomodoro.stop()
                } label: {
                    Label("Arrêter", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            } else {
                Button {
                    pomodoro.start()
                } label: {
                    Label("Démarrer", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            }
        }
    }
}

/// Sheet de configuration de l'intégration Crypto : choix de la devise et de la monnaie.
struct CryptoConfigSheet: View {
    @EnvironmentObject var live: LiveAppsStation

    var body: some View {
        SheetScaffold("Crypto",
                      subtitle: "Cours mis à jour toutes les 60 s (CoinGecko).",
                      live: true) {
            HStack(spacing: 12) {
                Picker("Crypto", selection: Binding(get: { live.coinID }, set: { live.setCoin($0) })) {
                    ForEach(DataService.coins) { Text($0.symbol).tag($0.id) }
                }
                .frame(width: 160)
                Picker("Devise", selection: Binding(get: { live.currency }, set: { live.setCurrency($0) })) {
                    Text("EUR").tag("eur"); Text("USD").tag("usd")
                }
                .frame(width: 140)
                Spacer()
                if live.cryptoOn, let p = live.cryptoPrice {
                    Text("\(live.coinSymbol) \(p >= 100 ? String(Int(p.rounded())) : String(format: "%.2f", p))\(live.currencySymbol)")
                        .font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

/// Sheet de statut de l'intégration Calendrier : accès, prochain événement, actualisation.
/// (Le calendrier n'a pas de réglage : il affiche le prochain événement à venir.)
struct CalendarConfigSheet: View {
    @EnvironmentObject var calendarStation: CalendarStation
    @State private var refreshing = false

    var body: some View {
        SheetScaffold("Calendrier",
                      subtitle: "Affiche le prochain événement de tes calendriers Apple sur la matrice.",
                      live: true) {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(calendarStation.lastError == nil ? Theme.online : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    if let error = calendarStation.lastError {
                        Text(error).font(.callout).foregroundStyle(Theme.textPrimary)
                        Text("Autorise Lumo dans Réglages Système → Confidentialité → Calendriers.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    } else if !calendarStation.enabled {
                        Text("Intégration désactivée").font(.callout).foregroundStyle(Theme.textPrimary)
                        Text("Active « Calendrier » dans la section Écran pour l'ajouter à la rotation.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(calendarStation.nextEventText ?? String(localized: "Aucun événement à venir"))
                            .font(.callout).foregroundStyle(Theme.textPrimary)
                        Text("Mis à jour automatiquement.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
            }

            HStack {
                Button {
                    refreshing = true
                    Task { await calendarStation.refresh(); refreshing = false }
                } label: {
                    if refreshing { ProgressView().controlSize(.small) }
                    else { Label("Actualiser", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .disabled(!calendarStation.enabled)
                Spacer()
            }
        }
    }

    private var statusIcon: String {
        if calendarStation.lastError != nil { return "exclamationmark.triangle.fill" }
        return calendarStation.enabled ? "checkmark.circle.fill" : "calendar"
    }
}

/// Sheet d'une app personnalisée de la rotation (créée dans Studio ou via l'API) :
/// l'afficher immédiatement, ou la supprimer de l'afficheur.
struct CustomAppSheet: View {
    let name: String
    let client: AwtrixClient
    var onShown: () -> Void = {}
    var onDeleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(name.capitalized,
                      subtitle: "App personnalisée, envoyée depuis Studio ou l'API.",
                      live: true) {
            HStack(spacing: 12) {
                Button {
                    Task {
                        try? await client.switchApp(name: name)
                        onShown()
                        dismiss()
                    }
                } label: {
                    Label("Afficher maintenant", systemImage: "play.fill")
                }
                .buttonStyle(PillButtonStyle())

                Spacer()

                Button(role: .destructive) {
                    Task {
                        try? await client.deleteCustomApp(name: name)
                        onDeleted()
                        dismiss()
                    }
                } label: {
                    Label("Supprimer de l'afficheur", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }
            Text("Supprimée, elle disparaît de la rotation ; renvoie-la depuis Studio pour la retrouver.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }
}
