import AppKit
import Observation

/// État d'attention de l'app : premier plan et fenêtres réellement visibles.
/// Les boucles de rafraîchissement s'en servent pour lever le pied quand personne
/// ne regarde — inutile de solliciter l'afficheur (et le Wi-Fi) à pleine cadence
/// pendant que Lumo est derrière une autre fenêtre.
@MainActor
@Observable
final class AppActivity {
    static let shared = AppActivity()

    /// Lumo est l'app au premier plan.
    private(set) var isForeground: Bool
    /// Au moins une fenêtre de Lumo est visible à l'écran (pas masquée ni réduite).
    private(set) var isVisible: Bool

    private init() {
        let app = NSApplication.shared
        isForeground = app.isActive
        isVisible = app.occlusionState.contains(.visible)

        observe(NSApplication.didBecomeActiveNotification) { $0.isForeground = true }
        observe(NSApplication.didResignActiveNotification) { $0.isForeground = false }
        observe(NSApplication.didChangeOcclusionStateNotification) {
            $0.isVisible = NSApplication.shared.occlusionState.contains(.visible)
        }
    }

    private func observe(_ name: Notification.Name, _ apply: @escaping @MainActor (AppActivity) -> Void) {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { apply(self) }
        }
    }
}
