import Foundation

/// Sous-ensemble des réglages exposés par GET/POST /api/settings que Lumo pilote.
struct AwtrixSettings: Codable, Sendable {
    var BRI: Int?        // luminosité 0…255
    var ABRI: Bool?      // luminosité automatique
    var ATRANS: Bool?    // transition automatique entre apps
    var ATIME: Int?      // durée d'affichage par app (s)
    var TEFF: Int?       // effet de transition
    var TSPEED: Int?     // vitesse de transition (ms)
    var TCOL: Int?       // couleur de texte par défaut (entier RGB)
    var SOM: Bool?       // bip de démarrage / sons
    // Apps intégrées (affichées dans la rotation)
    var TIM: Bool?       // Heure
    var DAT: Bool?       // Date
    var TEMP: Bool?      // Température
    var HUM: Bool?       // Humidité
    var BAT: Bool?       // Batterie
}
