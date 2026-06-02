import Foundation

/// Constantes et secrets injectés hors du code source.
enum AppInfo {
    /// Guide d'installation du firmware AWTRIX sur l'afficheur.
    static let flashGuideURL = URL(string: "https://blueforcer.github.io/awtrix3/#/flasher")!

    /// Client ID Spotify, fourni via Info.plist (xcconfig non versionné). Vide si non configuré.
    static var spotifyClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String) ?? ""
    }
}
