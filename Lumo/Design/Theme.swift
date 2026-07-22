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
    /// `let` et non `var` : ces dégradés sont relus à chaque rendu, inutile de les reconstruire.
    static let accentGradient = LinearGradient(colors: [Color(hex: "FFD24D"), Color(hex: "FFB300")],
                                               startPoint: .top, endPoint: .bottom)

    /// Dégradé de fond de la fenêtre principale.
    static let backgroundGradient = LinearGradient(colors: [Color(hex: "14141B"), Color(hex: "0B0B0F")],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)

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
/// Le libellé du Toggle est rendu à gauche de la piste (masquable via .labelsHidden()).
struct ModernToggleStyle: ToggleStyle {
    @Environment(\.labelsVisibility) private var labelsVisibility

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            if labelsVisibility != .hidden {
                configuration.label
                    .foregroundStyle(Theme.textPrimary)
            }
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
}

/// Sélecteur segmenté maison, aux couleurs de Lumo (remplace les segmented pickers
/// bleu système dans les sheets) : une pilule par option, la sélection est dorée.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selection = option.value
                    }
                } label: {
                    Text(LocalizedStringKey(option.label))
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            Capsule().fill(selection == option.value
                                           ? AnyShapeStyle(Theme.accent)
                                           : AnyShapeStyle(Color.clear))
                        )
                        .foregroundStyle(selection == option.value
                                         ? Color.black.opacity(0.85) : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
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
