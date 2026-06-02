import Foundation

/// Une composition sauvegardée dans Lumo, renvoyable en 1 clic (résout la perte au reboot).
struct DisplayScene: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var text: String
    var colorHex: String
    var icon: String
    var rainbow: Bool = false
    var persist: Bool = true   // option `save` : survit au redémarrage du device

    /// Nom d'app AWTRIX sûr (alphanumérique).
    var appName: String {
        let cleaned = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return cleaned.isEmpty ? "scene_\(id.uuidString.prefix(4))" : cleaned
    }

    func payload() -> PushPayload {
        var p = PushPayload()
        p.text = text.isEmpty ? nil : text
        p.color = colorHex
        let trimmedIcon = icon.trimmingCharacters(in: .whitespaces)
        if !trimmedIcon.isEmpty { p.icon = trimmedIcon }
        if rainbow { p.rainbow = true }
        p.save = persist
        p.repeatCount = 1   // défile le texte en entier avant de passer à l'app suivante
        return p
    }
}
