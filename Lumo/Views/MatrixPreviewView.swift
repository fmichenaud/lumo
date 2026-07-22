import SwiftUI

/// Rendu de la matrice 32×8 : LEDs arrondies nettes sur fond sombre.
/// Travaille sur des entiers bruts (0xRRGGBB) — calcul direct, pas de conversion NSColor.
struct MatrixPreviewView: View {
    let pixels: [Int]
    var columns = 32
    var rows = 8

    var body: some View {
        Canvas { context, size in
            let gap = max(1, size.width * 0.006)
            let cell = (size.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
            let radius = cell * 0.28
            let corner = CGSize(width: radius, height: radius)

            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10),
                with: .color(Theme.matrixBackground)
            )

            // Les LEDs éteintes (le gros de la matrice) partent en un seul remplissage,
            // et les couleurs allumées sont mémorisées : à 25 img/s, 256 Path + 256 Color
            // par image coûtaient plus cher que le dessin lui-même.
            var dark = Path()
            var palette: [Int: Color] = [:]

            for row in 0..<rows {
                for col in 0..<columns {
                    let index = row * columns + col
                    let v = index < pixels.count ? pixels[index] : 0
                    let r = (v >> 16) & 0xFF
                    let g = (v >> 8) & 0xFF
                    let b = v & 0xFF
                    let lum = (299 * r + 587 * g + 114 * b) / 1000

                    let x = gap + CGFloat(col) * (cell + gap)
                    let y = gap + CGFloat(row) * (cell + gap)
                    let rect = CGRect(x: x, y: y, width: cell, height: cell)

                    if lum < 6 {
                        dark.addRoundedRect(in: rect, cornerSize: corner)
                    } else {
                        let color: Color
                        if let known = palette[v] {
                            color = known
                        } else {
                            color = Color(rgb24: v)
                            palette[v] = color
                        }
                        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
                    }
                }
            }
            if !dark.isEmpty {
                context.fill(dark, with: .color(.white.opacity(0.03)))
            }
        }
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}
