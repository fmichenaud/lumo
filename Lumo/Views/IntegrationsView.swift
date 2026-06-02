import SwiftUI
import AppKit

/// Section Intégrations : connecte n'importe quelle API et affiche-la en direct.
struct IntegrationsView: View {
    let device: Device
    @EnvironmentObject var connectors: ConnectorsStation
    @State private var editing: Connector?
    @State private var showTemplates = false

    var body: some View {
        VStack(spacing: 14) {
            if connectors.connectors.isEmpty {
                empty
            } else {
                ForEach(connectors.connectors) { row($0) }
            }
            Button { showTemplates = true } label: {
                Label("Ajouter un connecteur", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
        .sheet(isPresented: $showTemplates) {
            TemplatePicker { template in
                showTemplates = false
                editing = template.build()
            }
        }
        .sheet(item: $editing) { connector in
            ConnectorEditor(device: device, connector: connector)
                .environmentObject(connectors)
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right").font(.title2)
            Text("Aucun connecteur").font(.callout)
            Text("Branche ta propre API ou une API externe (cours, capteurs, compteurs…).")
                .font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func row(_ c: Connector) -> some View {
        HStack(spacing: 12) {
            IconThumbnail(host: device.host, iconID: c.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name.isEmpty ? "Sans nom" : c.name).foregroundStyle(Theme.textPrimary)
                if let err = connectors.lastError[c.id] {
                    Text(err).font(.caption2).foregroundStyle(.red.opacity(0.9))
                } else if let val = connectors.lastValue[c.id] {
                    Text(c.renderedText(value: val)).font(.caption).foregroundStyle(Theme.accent)
                } else {
                    Text("Toutes les \(c.intervalSeconds) s").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Button { editing = c } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            Toggle("", isOn: Binding(get: { c.enabled }, set: { connectors.setEnabled(c, $0) }))
                .labelsHidden().tint(Theme.accent)
        }
    }
}

/// Galerie de modèles prêts à l'emploi : recherche + sections par catégorie, cartes élégantes.
private struct TemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (ConnectorTemplate) -> Void
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 320), spacing: 12)]

    private var filtered: [ConnectorTemplate] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ConnectorTemplate.all }
        return ConnectorTemplate.all.filter {
            $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) || $0.category.lowercased().contains(q)
        }
    }

    private var categories: [String] {
        let present = Set(filtered.map(\.category))
        return ConnectorTemplate.categoryOrder.filter(present.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ajouter un connecteur").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                        Text("Choisis un modèle — tout reste ajustable ensuite.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Rechercher un modèle…", text: $query).textFieldStyle(.plain)
                }
                .padding(10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: String.LocalizationValue(category)).uppercased())
                                .font(.caption.weight(.semibold)).tracking(0.8)
                                .foregroundStyle(Theme.textSecondary)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(filtered.filter { $0.category == category }) { card($0) }
                            }
                        }
                    }
                    if filtered.isEmpty {
                        Text("Aucun modèle pour « \(query) »")
                            .font(.callout).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.top, 30)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 600, height: 560)
        .background(Theme.background)
    }

    private func card(_ t: ConnectorTemplate) -> some View {
        Button { onPick(t) } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.14)).frame(width: 38, height: 38)
                    Image(systemName: t.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title).font(.callout.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(t.subtitle).font(.caption2).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
        }
        .buttonStyle(.plain)
    }
}

/// Éditeur d'un connecteur, organisé par sections claires.
private struct ConnectorEditor: View {
    let device: Device
    @EnvironmentObject var connectors: ConnectorsStation
    @Environment(\.dismiss) private var dismiss
    @State var connector: Connector
    @State private var testing = false
    @State private var authorizing = false
    @State private var testResult: String?
    @State private var showIconPicker = false
    @State private var advancedOAuth = false

    init(device: Device, connector: Connector) {
        self.device = device
        _connector = State(initialValue: connector)
        // Réglages techniques masqués par défaut pour les services préconfigurés.
        _advancedOAuth = State(initialValue: connector.auth.authURL.isEmpty)
    }

    private var isOfficialOAuth: Bool {
        !connector.auth.serviceName.isEmpty && !connector.auth.clientID.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(connector.name.isEmpty ? "Nouveau connecteur" : connector.name)
                    .font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)

                group("Source") {
                    field("Nom", "Mon API", text: $connector.name)
                    field("URL", "https://api.exemple.com/data", text: $connector.url)
                }

                group("Authentification") {
                    Picker("Méthode", selection: $connector.auth.kind) {
                        ForEach(AuthConfig.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    authFields
                }

                group("Donnée à afficher") {
                    field("Chemin JSON", "data.price ou items[0].value", text: $connector.jsonPath)
                    caption("La « route » vers la valeur dans la réponse JSON. Laisse vide si la réponse est déjà la valeur.")
                    field("Format affiché", "{value}€", text: $connector.template)
                    caption("« {value} » est remplacé par la valeur récupérée.")
                }

                group("Apparence") {
                    HStack(spacing: 12) {
                        ColorPicker("Couleur", selection: Binding(
                            get: { Color(hex: connector.colorHex) },
                            set: { connector.colorHex = $0.hexString }
                        ), supportsOpacity: false).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        IconThumbnail(host: device.host, iconID: connector.icon)
                        Button("Choisir une icône") { showIconPicker = true }
                            .buttonStyle(PillButtonStyle(prominent: false)).controlSize(.small)
                    }
                    Stepper("Rafraîchir toutes les \(connector.intervalSeconds) s",
                            value: $connector.intervalSeconds, in: 10...3600, step: 10)
                        .foregroundStyle(Theme.textPrimary)
                }

                Divider().overlay(Theme.stroke)
                actions
            }
            .padding(22)
        }
        .frame(width: 540, height: 620)
        .background(Theme.background)
        .sheet(isPresented: $showIconPicker) {
            IconImportSheet(device: device) { connector.icon = $0 }
        }
    }

    @ViewBuilder private var authFields: some View {
        switch connector.auth.kind {
        case .none:
            EmptyView()
        case .apiKey:
            field("Nom de l'en-tête", "X-API-Key", text: $connector.auth.headerName)
            field("Valeur de la clé", "votre clé", text: $connector.auth.apiKey)
        case .bearer:
            field("Token", "votre token d'accès", text: $connector.auth.bearerToken)
        case .oauth2:
            if isOfficialOAuth {
                // Service officiel : Client ID embarqué → connexion en 1 clic.
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.online)
                    Text("Connecte ton compte \(connector.auth.serviceName) en un clic.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            } else {
                oauthGuide
            }

            HStack(spacing: 10) {
                Button {
                    authorizing = true
                    Task { if let c = await connectors.authorize(connector) { connector = c }; authorizing = false }
                } label: {
                    if authorizing { ProgressView().controlSize(.small) }
                    else { Label(connector.auth.accessToken.isEmpty ? "Se connecter" : "Reconnecter", systemImage: "person.badge.key.fill") }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(connector.auth.clientID.isEmpty || connector.auth.authURL.isEmpty)
                if connector.auth.accessToken.isEmpty {
                    if connector.auth.clientID.isEmpty {
                        Text("↑ colle d'abord ton Client ID").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Label("Connecté", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.online)
                }
                Spacer()
            }

            DisclosureGroup(isExpanded: $advancedOAuth) {
                VStack(alignment: .leading, spacing: 8) {
                    field("Client ID", "fourni par le service", text: $connector.auth.clientID)
                    field("URL d'autorisation", "https://…/authorize", text: $connector.auth.authURL)
                    field("URL de token", "https://…/token", text: $connector.auth.tokenURL)
                    field("Scope", "read", text: $connector.auth.scope)
                    field("Client Secret (optionnel)", "rarement nécessaire", text: $connector.auth.clientSecret)
                    caption("Redirection à autoriser côté service : lumo://oauth")
                }
                .padding(.top, 6)
            } label: {
                Text("Réglages avancés").font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var oauthGuide: some View {
        let service = connector.auth.serviceName.isEmpty ? "ce service" : connector.auth.serviceName
        return VStack(alignment: .leading, spacing: 8) {
            Text("Connexion à \(service)").font(.callout.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text("Une seule fois, en 3 étapes :").font(.caption2).foregroundStyle(Theme.textSecondary)

            step(1, "Ouvre l'espace développeur et crée une app (gratuit).") {
                if let url = URL(string: connector.auth.helpURL), !connector.auth.helpURL.isEmpty {
                    Link(destination: url) {
                        Label("Ouvrir", systemImage: "arrow.up.right.square").font(.caption2)
                    }.foregroundStyle(Theme.accent)
                }
            }
            step(2, "Colle cette URL de redirection dans l'app créée :") {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("lumo://oauth", forType: .string)
                } label: {
                    Label("lumo://oauth", systemImage: "doc.on.doc").font(.caption2.monospaced())
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            step(3, "Copie le « Client ID » et colle-le ci-dessous :") { EmptyView() }

            TextField("Client ID", text: $connector.auth.clientID).textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
    }

    private func step<Trailing: View>(_ n: Int, _ text: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.caption2.weight(.bold))
                .frame(width: 16, height: 16)
                .background(Theme.accent.opacity(0.2), in: Circle())
                .foregroundStyle(Theme.accent)
            Text(LocalizedStringKey(text)).font(.caption).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            trailing()
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                testing = true
                Task { testResult = await connectors.test(connector); testing = false }
            } label: {
                if testing { ProgressView().controlSize(.small) }
                else { Label("Tester", systemImage: "checkmark.circle") }
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            if let r = testResult {
                Text("→ « \(connector.renderedText(value: r)) »").font(.caption).foregroundStyle(Theme.accent)
            } else if let e = connectors.lastError[connector.id] {
                Text(e).font(.caption).foregroundStyle(.red)
            }
            Spacer()
            if connectors.connectors.contains(where: { $0.id == connector.id }) {
                Button(role: .destructive) { connectors.remove(connector); dismiss() } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.plain).foregroundStyle(.red)
            }
            Button("Annuler") { dismiss() }.buttonStyle(PillButtonStyle(prominent: false))
            Button("Enregistrer") { save() }.buttonStyle(PillButtonStyle()).disabled(connector.url.isEmpty)
        }
    }

    private func save() {
        if connectors.connectors.contains(where: { $0.id == connector.id }) {
            connectors.update(connector)
        } else {
            connectors.add(connector)
        }
        dismiss()
    }

    // MARK: - Composants

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: String.LocalizationValue(title)).uppercased()).font(.caption.weight(.semibold)).tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }

    private func field(_ title: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title)).font(.caption2).foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func caption(_ t: String) -> some View {
        Text(LocalizedStringKey(t)).font(.caption2).foregroundStyle(Theme.textSecondary.opacity(0.8))
    }
}
