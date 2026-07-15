import SwiftUI

/// Gabarit commun de toutes les sheets de Lumo.
///
/// Deux familles d'usage :
/// - **réglage direct** (`live: true`) : chaque changement s'applique immédiatement,
///   un badge « appliqué en direct » le signale, la sheet se ferme par ✕ ou Échap ;
/// - **éditeur** : transactionnel, le contenu se termine par `EditorButtons`
///   (Annuler / Enregistrer) ; le ✕ et Échap équivalent à Annuler.
struct SheetScaffold<Content: View, Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var width: CGFloat = 520
    var height: CGFloat? = nil
    var live: Bool = false
    @ViewBuilder var content: () -> Content
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.dismiss) private var dismiss

    init(_ title: String,
         subtitle: String? = nil,
         width: CGFloat = 520,
         height: CGFloat? = nil,
         live: Bool = false,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.height = height
        self.live = live
        self.content = content
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content()
        }
        .padding(22)
        .frame(width: width, height: height, alignment: .top)
        .background(Theme.background)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if live { liveBadge }
            accessory()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2)
            }
            .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            .keyboardShortcut(.cancelAction)
            .help("Fermer (Échap)")
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.online).frame(width: 6, height: 6)
            Text("appliqué en direct").font(.caption2)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.white.opacity(0.05), in: Capsule())
        .padding(.top, 2)
    }
}

/// Pied standard des sheets « éditeur » : suppression optionnelle à gauche,
/// Annuler / Enregistrer à droite. À placer en fin de contenu, après un Divider.
struct EditorButtons: View {
    var onDelete: (() -> Void)? = nil
    var saveDisabled: Bool = false
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 10) {
            if let onDelete {
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain).foregroundStyle(.red)
                .help("Supprimer")
            }
            Spacer()
            Button("Annuler") { dismiss() }
                .buttonStyle(PillButtonStyle(prominent: false))
            Button("Enregistrer") { onSave() }
                .buttonStyle(PillButtonStyle())
                .disabled(saveDisabled)
        }
    }
}
