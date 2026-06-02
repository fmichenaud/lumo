import SwiftUI
import AppKit

/// Palette et constantes de style de Lumo.
enum Theme {
    static let accent = Color(hex: "FFC400")          // doré signature
    static let background = Color(hex: "0E0E12")
    static let surface = Color(hex: "17171E")
    static let surfaceHover = Color(hex: "20202A")
    static let stroke = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let online = Color(hex: "3DD68C")
    static let matrixBackground = Color(hex: "08080C")

    static let corner: CGFloat = 14

    /// Dégradé doré pour les éléments proéminents (boutons, logo).
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: "FFD24D"), Color(hex: "FFB300")],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Dégradé de fond de la fenêtre principale.
    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: "14141B"), Color(hex: "0B0B0F")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

}

extension Color {
    /// Construit une couleur à partir d'un entier 24 bits 0xRRGGBB (format /api/screen).
    init(rgb24: Int) {
        let r = Double((rgb24 >> 16) & 0xFF) / 255.0
        let g = Double((rgb24 >> 8) & 0xFF) / 255.0
        let b = Double(rgb24 & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Construit une couleur à partir d'une chaîne hexadécimale ("#RRGGBB" ou "RRGGBB").
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Représentation "#RRGGBB" attendue par l'API AWTRIX.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Composantes RGB 0–255, format attendu par les indicateurs AWTRIX.
    var rgbArray: [Int] {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return [Int(round(ns.redComponent * 255)),
                Int(round(ns.greenComponent * 255)),
                Int(round(ns.blueComponent * 255))]
    }

}

/// Switch moderne (piste arrondie, bouton coulissant, ressort), doré quand actif.
struct ModernToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? Theme.accent : Color.white.opacity(0.12))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
                Circle()
                    .fill(.white)
                    .padding(3)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: configuration.isOn ? 9 : -9)
            }
            .frame(width: 46, height: 28)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

/// Bouton plein, arrondi, avec retour visuel au survol/clic.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var prominent: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Theme.textPrimary)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .glassEffect(
                prominent ? .regular.tint(tint).interactive() : .regular.interactive(),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
