import SwiftUI

/// Récupère en boucle le contenu réel de la matrice (/api/screen) pour l'aperçu live.
/// Publie les pixels en entiers bruts (0xRRGGBB) pour un rendu rapide, sans conversion couleur.
@MainActor
final class ScreenStreamer: ObservableObject {
    @Published var pixels: [Int] = Array(repeating: 0, count: 256)
    @Published var isLive = false

    private var task: Task<Void, Never>?
    private let interval: UInt64 = 40_000_000 // 40 ms entre deux relevés (l'ESP répond en ~40 ms → ~12-15 img/s)

    func start(host: String) {
        stop()
        task = Task { [weak self] in
            let client = AwtrixClient(host: host)
            var failures = 0
            while !Task.isCancelled {
                if let raw = try? await client.fetchScreen(), raw.count >= 256 {
                    let next = Array(raw.prefix(256))
                    if next != self?.pixels { self?.pixels = next }   // pas de redraw si inchangé
                    self?.isLive = true
                    failures = 0
                } else {
                    failures += 1
                    if failures > 2 { self?.isLive = false }
                }
                try? await Task.sleep(nanoseconds: self?.interval ?? 400_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isLive = false
    }
}
