import AppIntents
import Foundation

// MARK: - Erreurs d'intent

/// Erreurs présentées à l'utilisateur dans Raccourcis / Siri (messages en français).
enum LumoIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noDevice
    case deviceNotFound(String)
    case invalidColor(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noDevice:
            return "Aucun afficheur n'est configuré dans Lumo. Ouvre l'app et ajoute ton appareil d'abord."
        case .deviceNotFound(let name):
            return "Aucun afficheur nommé « \(name) » n'est configuré dans Lumo."
        case .invalidColor(let hex):
            return "Couleur invalide : « \(hex) ». Utilise un code hexadécimal comme #FF5555."
        }
    }
}

// MARK: - Résolution du device

/// Les intents peuvent s'exécuter sans que l'UI (et donc `DeviceStore`) ne soit construite :
/// on relit directement la liste persistée par `DeviceStore` dans UserDefaults.
enum IntentDeviceResolver {
    private static let storageKey = "lumo.devices.v1"

    /// Devices connus, tels que persistés par l'app.
    static func devices() -> [Device] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Device].self, from: data) else { return [] }
        return saved
    }

    /// Retourne le device demandé par nom (insensible à la casse et aux accents),
    /// ou le premier device connu si aucun nom n'est fourni.
    static func resolve(named name: String?) throws -> Device {
        let known = devices()
        guard !known.isEmpty else { throw LumoIntentError.noDevice }

        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return known[0]
        }
        let wanted = name.trimmingCharacters(in: .whitespaces)
        if let match = known.first(where: {
            $0.name.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return match
        }
        // Tolérance : correspondance partielle ("salon" trouve "TC001 Salon").
        if let match = known.first(where: {
            $0.name.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }) {
            return match
        }
        throw LumoIntentError.deviceNotFound(wanted)
    }

    /// Client HTTP prêt à l'emploi pour le device résolu.
    static func client(named name: String?) throws -> AwtrixClient {
        AwtrixClient(host: try resolve(named: name).host)
    }
}

/// Normalise une couleur hexadécimale saisie librement ("ff5555", "#FF5555") en "#RRGGBB".
/// Jette une erreur en français si le format est invalide.
private func normalizedHexColor(_ raw: String) throws -> String {
    var hex = raw.trimmingCharacters(in: .whitespaces).uppercased()
    if hex.hasPrefix("#") { hex.removeFirst() }
    let valid = hex.count == 6 && hex.allSatisfy { $0.isHexDigit }
    guard valid else { throw LumoIntentError.invalidColor(raw) }
    return "#\(hex)"
}

// MARK: - Intents

/// Envoie une notification éphémère (POST /api/notify).
struct SendNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Envoyer une notification"
    static let description = IntentDescription(
        "Affiche brièvement un message sur l'afficheur AWTRIX, comme une notification.",
        categoryName: "Affichage"
    )

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Couleur (hex)", description: "Code hexadécimal du texte, ex. #FF5555")
    var colorHex: String?

    @Parameter(title: "Icône", description: "Identifiant d'icône LaMetric, ex. 1234")
    var icon: String?

    @Parameter(title: "Garder affichée", description: "La notification reste à l'écran jusqu'à confirmation.", default: false)
    var hold: Bool

    @Parameter(title: "Appareil", description: "Nom de l'afficheur dans Lumo. Par défaut : le premier appareil.")
    var deviceName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Envoyer \(\.$message) sur l'afficheur") {
            \.$colorHex
            \.$icon
            \.$hold
            \.$deviceName
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = try IntentDeviceResolver.client(named: deviceName)
        var payload = PushPayload()
        payload.text = message
        payload.color = try colorHex.map(normalizedHexColor)
        payload.icon = icon?.trimmingCharacters(in: .whitespaces)
        payload.hold = hold ? true : nil
        payload.wakeup = true
        try await client.notify(payload)
        return .result(dialog: "Notification envoyée sur l'afficheur.")
    }
}

/// Crée/actualise une app custom permanente puis bascule dessus (POST /api/custom + /api/switch).
struct ShowTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Afficher un texte en continu"
    static let description = IntentDescription(
        "Ajoute le texte comme app permanente dans la rotation de l'afficheur et l'affiche immédiatement.",
        categoryName: "Affichage"
    )

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Nom d'app", description: "Nom de l'app custom dans la rotation.", default: "raccourci")
    var appName: String

    @Parameter(title: "Couleur (hex)", description: "Code hexadécimal du texte, ex. #FF5555")
    var colorHex: String?

    @Parameter(title: "Appareil", description: "Nom de l'afficheur dans Lumo. Par défaut : le premier appareil.")
    var deviceName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Afficher \(\.$message) en continu") {
            \.$appName
            \.$colorHex
            \.$deviceName
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = try IntentDeviceResolver.client(named: deviceName)
        var payload = PushPayload()
        payload.text = message
        payload.color = try colorHex.map(normalizedHexColor)
        try await client.upsertCustomApp(name: appName, payload: payload)
        try await client.switchApp(name: appName)
        return .result(dialog: "Texte affiché en continu dans l'app « \(appName) ».")
    }
}

/// Bascule la rotation sur une app donnée (POST /api/switch).
struct SwitchAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Basculer sur une app"
    static let description = IntentDescription(
        "Affiche immédiatement l'app demandée sur l'afficheur (ex. Time, weather, raccourci).",
        categoryName: "Affichage"
    )

    @Parameter(title: "Nom de l'app", description: "Nom exact de l'app, ex. Time, weather.")
    var appName: String

    @Parameter(title: "Appareil", description: "Nom de l'afficheur dans Lumo. Par défaut : le premier appareil.")
    var deviceName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Basculer sur l'app \(\.$appName)") {
            \.$deviceName
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = try IntentDeviceResolver.client(named: deviceName)
        try await client.switchApp(name: appName)
        return .result(dialog: "Afficheur basculé sur « \(appName) ».")
    }
}

/// Allume ou éteint la matrice (POST /api/power).
struct SetPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Allumer ou éteindre l'écran"
    static let description = IntentDescription(
        "Allume ou éteint la matrice LED de l'afficheur.",
        categoryName: "Écran"
    )

    @Parameter(title: "Allumer", description: "Activé : allume l'écran. Désactivé : l'éteint.", default: true)
    var on: Bool

    @Parameter(title: "Appareil", description: "Nom de l'afficheur dans Lumo. Par défaut : le premier appareil.")
    var deviceName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Mettre l'écran sur \(\.$on)") {
            \.$deviceName
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = try IntentDeviceResolver.client(named: deviceName)
        try await client.setPower(on)
        return .result(dialog: on ? "Écran allumé." : "Écran éteint.")
    }
}

/// Règle la luminosité (POST /api/settings, BRI 1…255).
struct SetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Régler la luminosité"
    static let description = IntentDescription(
        "Règle la luminosité de l'afficheur, de 1 à 100 %. Désactive la luminosité automatique.",
        categoryName: "Écran"
    )

    @Parameter(title: "Luminosité (%)", description: "De 1 à 100.", inclusiveRange: (1, 100))
    var brightness: Int

    @Parameter(title: "Appareil", description: "Nom de l'afficheur dans Lumo. Par défaut : le premier appareil.")
    var deviceName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Régler la luminosité à \(\.$brightness) %") {
            \.$deviceName
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = try IntentDeviceResolver.client(named: deviceName)
        // 1…100 % → 1…255 (jamais 0 : 0 éteindrait quasi l'écran, l'intent Power est là pour ça).
        let clamped = max(1, min(100, brightness))
        let raw = max(1, Int((Double(clamped) / 100.0 * 255.0).rounded()))
        try await client.setBrightness(raw)
        return .result(dialog: "Luminosité réglée à \(clamped) %.")
    }
}

// MARK: - Raccourcis proposés (Spotlight / Siri)

struct LumoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendNotificationIntent(),
            phrases: [
                "Envoie une notification avec \(.applicationName)",
                "Envoie un message sur l'afficheur avec \(.applicationName)"
            ],
            shortTitle: "Envoyer une notification",
            systemImageName: "bell.badge"
        )
        AppShortcut(
            intent: SetPowerIntent(),
            phrases: [
                "Allume l'afficheur avec \(.applicationName)",
                "Éteins l'afficheur avec \(.applicationName)"
            ],
            shortTitle: "Allumer ou éteindre l'écran",
            systemImageName: "power"
        )
        AppShortcut(
            intent: SetBrightnessIntent(),
            phrases: [
                "Règle la luminosité de l'afficheur avec \(.applicationName)"
            ],
            shortTitle: "Régler la luminosité",
            systemImageName: "sun.max"
        )
    }
}
