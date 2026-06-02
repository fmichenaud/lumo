import Foundation

/// Corps JSON commun à /api/notify et /api/custom.
/// Les champs nil ne sont pas encodés (l'encodeur les omet), donc un payload vide = "{}".
struct PushPayload: Encodable, Sendable {
    var text: String?
    var icon: String?
    var color: String?          // "#RRGGBB"
    var background: String?     // "#RRGGBB"
    var duration: Int?          // s (notify)
    var rainbow: Bool?
    var center: Bool?
    var noScroll: Bool?
    var pushIcon: Int?          // 0 fixe, 1 défile avec le texte, 2 défile en boucle
    var hold: Bool?             // notify : reste affiché
    var stack: Bool?
    var scrollSpeed: Int?       // %
    var repeatCount: Int?
    var wakeup: Bool?           // notify : réveille l'écran éteint
    var sound: String?          // nom de mélodie (dossier MELODIES)
    var rtttl: String?          // mélodie RTTTL inline
    var effect: String?         // effet de fond
    var save: Bool?             // persiste l'app custom après reboot
    var lifetime: Int?
    var progress: Int?          // barre de progression 0–100
    var progressC: String?
    var progressBC: String?
    var bar: [Int]?             // histogramme
    var line: [Int]?            // courbe
    var autoscale: Bool?

    enum CodingKeys: String, CodingKey {
        case text, icon, color, background, duration, rainbow, center
        case noScroll, pushIcon, hold, stack, scrollSpeed
        case wakeup, sound, rtttl, effect, save, lifetime
        case progress, progressC, progressBC, bar, line, autoscale
        case repeatCount = "repeat"
    }
}
