import Foundation
import Observation

/// Sondage partagé de l'afficheur : une seule boucle interroge /api/loop et /api/stats
/// pour toutes les vues du détail (barre « à l'écran », section Écran…), là où chacune
/// avait la sienne — deux fois moins de requêtes, et un état cohérent entre les vues.
///
/// La boucle appartient à `DeviceDetailView` : elle démarre avec la vue et s'annule
/// quand elle disparaît ou que l'afficheur change.
@MainActor
@Observable
final class DevicePoller {
    /// Rotation courante : nom d'app → position.
    private(set) var loop: [String: Int] = [:]
    /// App actuellement affichée par l'afficheur.
    private(set) var currentApp: String?

    private static let interval: UInt64 = 3_000_000_000

    /// Boucle de sondage, jusqu'à annulation de la tâche appelante.
    func run(host: String) async {
        loop = [:]
        currentApp = nil
        let client = AwtrixClient(host: host)
        while !Task.isCancelled {
            await refresh(client)
            try? await Task.sleep(nanoseconds: Self.interval)
        }
    }

    /// Relecture immédiate après une action utilisateur (toggle, suppression d'app…).
    func refreshNow(host: String) async {
        await refresh(AwtrixClient(host: host))
    }

    /// Reflète tout de suite un réordonnancement demandé par l'utilisateur, en attendant
    /// que l'afficheur confirme au prochain sondage.
    func applyOptimisticOrder(_ names: [String]) {
        var updated = loop
        for (index, name) in names.enumerated() where updated[name] != nil { updated[name] = index }
        if updated != loop { loop = updated }
    }

    /// N'assigne que ce qui a réellement changé : sans ça, chaque sondage invaliderait
    /// toutes les vues abonnées (toutes les 3 s, pour rien).
    private func refresh(_ client: AwtrixClient) async {
        if let fresh = try? await client.fetchLoop(), fresh != loop { loop = fresh }
        if let app = try? await client.fetchStats().app, app != currentApp { currentApp = app }
    }
}
