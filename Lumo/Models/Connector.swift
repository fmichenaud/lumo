import Foundation

/// Configuration d'authentification d'un connecteur.
struct AuthConfig: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case none, apiKey, bearer, oauth2
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:   return "Aucune"
            case .apiKey: return "Clé API (en-tête)"
            case .bearer: return "Token Bearer"
            case .oauth2: return "OAuth 2.0"
            }
        }
    }

    var kind: Kind = .none
    // Clé API
    var headerName: String = "Authorization"
    var apiKey: String = ""
    // Bearer
    var bearerToken: String = ""
    // OAuth2
    var authURL: String = ""
    var tokenURL: String = ""
    var clientID: String = ""
    var clientSecret: String = ""
    var scope: String = ""
    var accessToken: String = ""
    var helpURL: String = ""        // portail développeur du service (pour obtenir le Client ID)
    var serviceName: String = ""    // nom convivial du service (ex. "Spotify")

    var isAuthorized: Bool { kind != .oauth2 || !accessToken.isEmpty }
}

/// Un connecteur vers une API quelconque : récupère une valeur et l'affiche sur l'écran.
struct Connector: Identifiable, Codable, Hashable {
    /// Sources spéciales : services qui ne rentrent pas dans le moule URL + chemin JSON
    /// (agrégation multi-requêtes, token du Trousseau…). Voir SpecialSources.swift.
    enum SpecialSource: String, Codable {
        case claudeQuota    // quota Claude Code (session 5 h + semaine)
        case stripeMRR      // revenu mensuel récurrent Stripe
        case stripeTotal    // gain total net Stripe (encaissements − remboursements − frais)
    }

    /// Vrai pour les sources Stripe (partagent la clé API et le lien de création).
    var isStripe: Bool { special == .stripeMRR || special == .stripeTotal }

    var id = UUID()
    var special: SpecialSource?
    var name: String = ""
    var url: String = ""
    var auth = AuthConfig()
    var extraHeadersText: String = ""   // en-têtes additionnels "Clé: Valeur" par ligne
    var jsonPath: String = ""
    var template: String = "{value}"
    var fallbackText: String = ""   // affiché quand l'API ne renvoie aucune donnée (ex. Spotify en pause)
    var colorHex: String = "#FFC400"
    var icon: String = ""
    var intervalSeconds: Int = 60
    var enabled: Bool = false

    var appName: String {
        let cleaned = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return cleaned.isEmpty ? "api_\(id.uuidString.prefix(4))" : cleaned
    }

    func renderedText(value: String) -> String {
        template.replacingOccurrences(of: "{value}", with: value)
    }

    /// En-têtes finaux de la requête (auth + en-têtes additionnels).
    func requestHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        for line in extraHeadersText.split(whereSeparator: \.isNewline) {
            guard let sep = line.firstIndex(of: ":") else { continue }
            let key = line[..<sep].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { headers[key] = value }
        }
        switch auth.kind {
        case .none: break
        case .apiKey:
            if !auth.apiKey.isEmpty {
                headers[auth.headerName.isEmpty ? "Authorization" : auth.headerName] = auth.apiKey
            }
        case .bearer:
            if !auth.bearerToken.isEmpty { headers["Authorization"] = "Bearer \(auth.bearerToken)" }
        case .oauth2:
            if !auth.accessToken.isEmpty { headers["Authorization"] = "Bearer \(auth.accessToken)" }
        }
        return headers
    }
}

/// Modèle de connecteur prêt à l'emploi.
struct ConnectorTemplate: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String          // SF Symbol pour la vignette du modèle
    let category: String
    let build: () -> Connector

    /// Ordre d'affichage des catégories.
    static let categoryOrder = ["Crypto", "Devises", "Développeur", "Espace", "Fun", "Maison", "Services", "Custom"]

    private static func cg(_ id: String, _ sym: String, _ color: String, _ icon: String = "1013") -> Connector {
        Connector(name: sym,
                  url: "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=eur",
                  jsonPath: "\(id).eur", template: "\(sym) {value}€", colorHex: color, icon: icon, intervalSeconds: 60)
    }

    private static func fx(_ to: String, _ tmpl: String) -> Connector {
        Connector(name: "EUR→\(to)",
                  url: "https://open.er-api.com/v6/latest/EUR",
                  jsonPath: "rates.\(to)", template: tmpl, colorHex: "#3DD68C", icon: "616", intervalSeconds: 1800)
    }

    static let all: [ConnectorTemplate] = [
        // Crypto
        .init(title: "Bitcoin", subtitle: "Cours BTC en euros", symbol: "bitcoinsign.circle.fill", category: "Crypto") { cg("bitcoin", "BTC", "#F7931A", "857") },
        .init(title: "Ethereum", subtitle: "Cours ETH en euros", symbol: "e.circle.fill", category: "Crypto") { cg("ethereum", "ETH", "#627EEA", "9013") },
        .init(title: "Solana", subtitle: "Cours SOL en euros", symbol: "s.circle.fill", category: "Crypto") { cg("solana", "SOL", "#14F195") },
        .init(title: "Dogecoin", subtitle: "Cours DOGE en euros", symbol: "d.circle.fill", category: "Crypto") { cg("dogecoin", "DOGE", "#C2A633") },
        .init(title: "Cardano", subtitle: "Cours ADA en euros", symbol: "a.circle.fill", category: "Crypto") { cg("cardano", "ADA", "#0033AD") },
        .init(title: "XRP", subtitle: "Cours XRP en euros", symbol: "x.circle.fill", category: "Crypto") {
            Connector(name: "XRP", url: "https://api.coingecko.com/api/v3/simple/price?ids=ripple&vs_currencies=eur",
                      jsonPath: "ripple.eur", template: "XRP {value}€", colorHex: "#23292F", icon: "1013", intervalSeconds: 60)
        },
        .init(title: "BTC variation 24h", subtitle: "Évolution sur 24 h", symbol: "chart.line.uptrend.xyaxis", category: "Crypto") {
            Connector(name: "BTC 24h", url: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=eur&ids=bitcoin",
                      jsonPath: "0.price_change_percentage_24h", template: "BTC {value}%", colorHex: "#F7931A", icon: "857", intervalSeconds: 300)
        },
        .init(title: "Fear & Greed", subtitle: "Indice de sentiment crypto", symbol: "gauge.medium", category: "Crypto") {
            Connector(name: "Fear&Greed", url: "https://api.alternative.me/fng/",
                      jsonPath: "data.0.value", template: "F&G {value}", colorHex: "#FF6B6B", icon: "1013", intervalSeconds: 3600)
        },

        // Devises
        .init(title: "Euro → Dollar", subtitle: "Taux EUR/USD", symbol: "dollarsign.circle.fill", category: "Devises") { fx("USD", "€$ {value}") },
        .init(title: "Euro → Livre", subtitle: "Taux EUR/GBP", symbol: "sterlingsign.circle.fill", category: "Devises") { fx("GBP", "€£ {value}") },
        .init(title: "Euro → Yen", subtitle: "Taux EUR/JPY", symbol: "yensign.circle.fill", category: "Devises") { fx("JPY", "€¥ {value}") },

        // Développeur
        .init(title: "Étoiles GitHub", subtitle: "Stars d'un dépôt (édite l'URL)", symbol: "star.fill", category: "Développeur") {
            Connector(name: "GitHub Stars", url: "https://api.github.com/repos/Blueforcer/awtrix3",
                      jsonPath: "stargazers_count", template: "★ {value}", colorHex: "#FFFFFF", icon: "305", intervalSeconds: 600)
        },
        .init(title: "Abonnés GitHub", subtitle: "Followers d'un utilisateur", symbol: "person.crop.circle.badge.plus", category: "Développeur") {
            Connector(name: "GitHub Followers", url: "https://api.github.com/users/torvalds",
                      jsonPath: "followers", template: "{value} abonnés", colorHex: "#FFFFFF", icon: "305", intervalSeconds: 600)
        },
        .init(title: "Téléchargements npm", subtitle: "Downloads/semaine d'un paquet", symbol: "shippingbox.fill", category: "Développeur") {
            Connector(name: "npm", url: "https://api.npmjs.org/downloads/point/last-week/react",
                      jsonPath: "downloads", template: "{value} dl", colorHex: "#CB3837", icon: "305", intervalSeconds: 3600)
        },

        // Espace
        .init(title: "Altitude ISS", subtitle: "Station spatiale en direct", symbol: "globe.europe.africa.fill", category: "Espace") {
            Connector(name: "ISS Altitude", url: "https://api.wheretheiss.at/v1/satellites/25544",
                      jsonPath: "altitude", template: "ISS {value}km", colorHex: "#3DD68C", icon: "542", intervalSeconds: 30)
        },
        .init(title: "Vitesse ISS", subtitle: "Vitesse orbitale", symbol: "speedometer", category: "Espace") {
            Connector(name: "ISS Vitesse", url: "https://api.wheretheiss.at/v1/satellites/25544",
                      jsonPath: "velocity", template: "{value} km/h", colorHex: "#3DD68C", icon: "542", intervalSeconds: 30)
        },

        // Fun
        .init(title: "Conseil du jour", subtitle: "Une phrase de sagesse", symbol: "quote.bubble.fill", category: "Fun") {
            Connector(name: "Conseil", url: "https://api.adviceslip.com/advice",
                      jsonPath: "slip.advice", template: "{value}", colorHex: "#FFC400", icon: "1475", intervalSeconds: 600)
        },
        .init(title: "Fait sur les chats", subtitle: "Anecdote féline", symbol: "cat.fill", category: "Fun") {
            Connector(name: "Chat", url: "https://catfact.ninja/fact",
                      jsonPath: "fact", template: "{value}", colorHex: "#FFC400", intervalSeconds: 600)
        },
        .init(title: "Blague", subtitle: "Dad joke (en-tête Accept)", symbol: "face.smiling.fill", category: "Fun") {
            var c = Connector(name: "Blague", url: "https://icanhazdadjoke.com/",
                              jsonPath: "joke", template: "{value}", colorHex: "#FFC400", intervalSeconds: 600)
            c.extraHeadersText = "Accept: application/json"
            return c
        },

        // Maison / perso
        .init(title: "Home Assistant", subtitle: "État d'un capteur (token)", symbol: "house.fill", category: "Maison") {
            var c = Connector(name: "Home Assistant",
                              url: "https://VOTRE-HA:8123/api/states/sensor.CAPTEUR",
                              jsonPath: "state", template: "{value}", colorHex: "#41BDF5", icon: "96", intervalSeconds: 60)
            c.auth.kind = .bearer
            return c
        },

        // Services (sources spéciales / OAuth)
        .init(title: "Quota Claude Code", subtitle: "Session 5 h + semaine, via le Trousseau — rien à configurer", symbol: "sparkles", category: "Services") {
            var c = Connector(name: "Claude", template: "CC {value}", colorHex: "#3DD68C", intervalSeconds: 60)
            c.special = .claudeQuota
            return c
        },
        .init(title: "MRR Stripe", subtitle: "Revenu mensuel récurrent, calculé depuis tes abonnements", symbol: "creditcard.fill", category: "Services") {
            var c = Connector(name: "MRR", template: "MRR {value}", colorHex: "#8A7DFF", intervalSeconds: 1800)
            c.special = .stripeMRR
            c.auth.kind = .bearer
            return c
        },
        .init(title: "Gain total Stripe", subtitle: "Encaissements nets cumulés (remboursements et frais déduits)", symbol: "banknote.fill", category: "Services") {
            var c = Connector(name: "Total", template: "Total {value}", colorHex: "#8A7DFF", intervalSeconds: 3600)
            c.special = .stripeTotal
            c.auth.kind = .bearer
            return c
        },
        .init(title: "Spotify – titre en cours", subtitle: "OAuth 2.0 (client requis)", symbol: "music.note", category: "Services") {
            var c = Connector(name: "Spotify",
                              url: "https://api.spotify.com/v1/me/player/currently-playing",
                              jsonPath: "item.name", template: "♪ {value}", fallbackText: "♪ ⏸", colorHex: "#1DB954",
                              icon: "647", intervalSeconds: 15)
            c.auth.kind = .oauth2
            c.auth.authURL = "https://accounts.spotify.com/authorize"
            c.auth.tokenURL = "https://accounts.spotify.com/api/token"
            c.auth.scope = "user-read-currently-playing"
            c.auth.serviceName = "Spotify"
            c.auth.helpURL = "https://developer.spotify.com/dashboard"
            c.auth.clientID = AppInfo.spotifyClientID  // injecté via Config/Secrets.xcconfig (vide → saisie manuelle)
            return c
        },

        // Custom
        .init(title: "API personnalisée", subtitle: "Pars d'une page vierge", symbol: "plus.rectangle.on.rectangle", category: "Custom") {
            Connector()
        }
    ]
}

/// Extraction d'une valeur depuis une réponse JSON via un chemin simple ("a.b[0].c").
enum JSONValue {
    static func extract(path: String, from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        var current: Any? = root
        if !trimmed.isEmpty {
            for token in tokens(trimmed) {
                if let index = Int(token) {
                    current = (current as? [Any])?[safe: index]
                } else {
                    current = (current as? [String: Any])?[token]
                }
                if current == nil { return nil }
            }
        }
        return stringify(current)
    }

    private static func tokens(_ path: String) -> [String] {
        path.replacingOccurrences(of: "[", with: ".")
            .replacingOccurrences(of: "]", with: "")
            .split(separator: ".")
            .map(String.init)
    }

    private static func stringify(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber:
            if n === kCFBooleanTrue || n === kCFBooleanFalse { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            return d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d)
        case .none: return nil
        default: return "\(value!)"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
