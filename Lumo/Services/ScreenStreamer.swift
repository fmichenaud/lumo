import SwiftUI
import Observation

/// Récupère en boucle le contenu réel de la matrice (/api/screen) pour l'aperçu live.
/// Publie les pixels en entiers bruts (0xRRGGBB) pour un rendu rapide, sans conversion couleur.
///
/// La cadence suit ce que l'utilisateur regarde vraiment : pleine vitesse quand l'aperçu
/// est déployé et Lumo au premier plan, quelques images/s pour la mini-matrice, au ralenti
/// en arrière-plan, et plus aucune requête quand aucune fenêtre n'est visible.
@MainActor
@Observable
final class ScreenStreamer {
    private(set) var pixels: [Int] = Array(repeating: 0, count: 256)
    private(set) var isLive = false

    private var task: Task<Void, Never>?
    private var expanded = false

    // L'ESP répond en ~40 ms : au-delà de 25 relevés/s, on n'affiche rien de plus.
    private static let expandedInterval: UInt64 = 40_000_000    // aperçu déployé
    private static let compactInterval: UInt64 = 200_000_000    // mini-matrice : 5 img/s suffisent
    private static let backgroundInterval: UInt64 = 1_000_000_000
    private static let hiddenInterval: UInt64 = 2_000_000_000   // fenêtres masquées : on ne sonde plus

    /// Cadence courante, selon l'attention portée à la fenêtre.
    private var interval: UInt64 {
        guard AppActivity.shared.isForeground else { return Self.backgroundInterval }
        return expanded ? Self.expandedInterval : Self.compactInterval
    }

    /// Prévient le streamer que l'aperçu est déployé (ou replié) : la cadence suit.
    func setExpanded(_ value: Bool) { expanded = value }

    func start(host: String) {
        stop()
        task = Task { [weak self] in
            let client = AwtrixClient(host: host)
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                // Aucune fenêtre visible : rien à rafraîchir, on n'interroge pas l'afficheur.
                guard AppActivity.shared.isVisible else {
                    try? await Task.sleep(nanoseconds: Self.hiddenInterval)
                    continue
                }
                if let raw = try? await client.fetchScreen(), raw.count >= 256 {
                    let next = Array(raw.prefix(256))
                    if next != self.pixels { self.pixels = next }   // pas de redraw si inchangé
                    if !self.isLive { self.isLive = true }          // ni si le statut n'a pas bougé
                    failures = 0
                } else {
                    failures += 1
                    if failures > 2, self.isLive { self.isLive = false }
                }
                try? await Task.sleep(nanoseconds: self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if isLive { isLive = false }
    }
}
