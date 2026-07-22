import SwiftUI

/// Éditeur pixel art 32×8 : peins au glissé, puis envoie sur l'afficheur via commandes `draw`.
struct DrawView: View {
    let device: Device
    @Environment(DeviceStore.self) var store
    var onResult: (String) -> Void = { _ in }

    @State private var pixels = [Color?](repeating: nil, count: 256)
    @State private var brush = Theme.accent
    @State private var eraser = false

    private let columns = 32
    private let rows = 8
    private var client: AwtrixClient { store.client(for: device) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ÉDITEUR PIXEL ART")
                .font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Theme.textSecondary)

            canvas
                .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke))

            HStack(spacing: 12) {
                ColorPicker("Pinceau", selection: $brush, supportsOpacity: false)
                    .foregroundStyle(Theme.textPrimary).frame(width: 130)
                Toggle(isOn: $eraser) { Text("Gomme").font(.caption) }
                Button("Tout effacer") { pixels = .init(repeating: nil, count: 256) }
                    .buttonStyle(PillButtonStyle(prominent: false)).controlSize(.small)
                Spacer()
                Button { Task { await send() } } label: {
                    Label("Envoyer le dessin", systemImage: "paintbrush.pointed.fill")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(pixels.allSatisfy { $0 == nil })
            }
        }
        .card()
    }

    private var canvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let cw = size.width / CGFloat(columns)
                let ch = size.height / CGFloat(rows)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.matrixBackground))
                for r in 0..<rows {
                    for c in 0..<columns {
                        let rect = CGRect(x: CGFloat(c) * cw + 1, y: CGFloat(r) * ch + 1,
                                          width: cw - 2, height: ch - 2)
                        let color = pixels[r * columns + c] ?? Color.white.opacity(0.04)
                        context.fill(Path(roundedRect: rect, cornerRadius: cw * 0.2), with: .color(color))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let cw = geo.size.width / CGFloat(columns)
                        let ch = geo.size.height / CGFloat(rows)
                        let c = Int(value.location.x / cw)
                        let r = Int(value.location.y / ch)
                        guard c >= 0, c < columns, r >= 0, r < rows else { return }
                        pixels[r * columns + c] = eraser ? nil : brush
                    }
            )
        }
    }

    private func send() async {
        // Construit les commandes draw : un "dp" (draw pixel) par pixel allumé.
        var commands: [[String: Any]] = []
        for r in 0..<rows {
            for c in 0..<columns {
                if let color = pixels[r * columns + c] {
                    commands.append(["dp": [c, r, color.hexString]])
                }
            }
        }
        guard !commands.isEmpty else { return }
        let json: [String: Any] = ["draw": commands, "duration": 15]
        do {
            try await client.upsertCustomAppRaw(name: "pixelart", json: json)
            try await client.switchApp(name: "pixelart")
            onResult("Dessin envoyé (\(commands.count) pixels)")
        } catch {
            onResult("Échec de l'envoi du dessin")
        }
    }
}
