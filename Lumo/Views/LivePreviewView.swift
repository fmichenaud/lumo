import SwiftUI

/// Aperçu live isolé : possède son propre ScreenStreamer, donc seul lui se redessine
/// quand les pixels changent (le reste du dashboard reste figé → bien plus fluide).
struct LivePreviewView: View {
    let host: String
    @StateObject private var screen = ScreenStreamer()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(screen.isLive ? Theme.online : Theme.textSecondary)
                    .frame(width: 7, height: 7)
                Text(screen.isLive ? "APERÇU LIVE" : "HORS LIGNE")
                    .font(.caption.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
            }
            MatrixPreviewView(pixels: screen.pixels)
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(Theme.matrixBackground, in: RoundedRectangle(cornerRadius: Theme.corner))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.stroke))
        }
        .card()
        .task(id: host) { screen.start(host: host) }
        .onDisappear { screen.stop() }
    }
}
