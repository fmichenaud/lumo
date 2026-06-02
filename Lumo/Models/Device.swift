import Foundation

/// Un afficheur AWTRIX connu de l'app (identifié par son uid stable).
struct Device: Identifiable, Codable, Hashable, Sendable {
    var id: String        // uid AWTRIX, ex. "awtrix_3d8c0c"
    var name: String      // nom convivial éditable
    var host: String      // adresse IP ou hostname
    var isFavorite: Bool = false

    /// Nom par défaut dérivé de l'uid à la découverte.
    static func defaultName(for uid: String) -> String {
        "Ulanzi TC001"
    }
}
