import Foundation

/// Une règle d'alerte : surveille une métrique et déclenche une notification
/// (et éventuellement une LED témoin) quand la valeur franchit un seuil,
/// ou se déclenche à heure fixe pour les règles planifiées.
struct AlertRule: Identifiable, Codable, Hashable {

    /// Type de déclencheur : franchissement de seuil ou horaire fixe.
    enum Trigger: String, Codable {
        case threshold, schedule
    }

    /// Ce qu'on surveille.
    enum Metric: String, Codable, CaseIterable, Identifiable {
        case macCPU, macRAM, deviceBattery, deviceTemp, deviceHumidity
        case claudeSession, claudeWeekly, stripeMRR, stripeTotal, connector
        var id: String { rawValue }

        var label: String {
            switch self {
            case .macCPU:         return String(localized: "CPU du Mac")
            case .macRAM:         return String(localized: "RAM du Mac")
            case .deviceBattery:  return String(localized: "Batterie de l'afficheur")
            case .deviceTemp:     return String(localized: "Température (capteur)")
            case .deviceHumidity: return String(localized: "Humidité (capteur)")
            case .claudeSession:  return String(localized: "Quota Claude — session")
            case .claudeWeekly:   return String(localized: "Quota Claude — semaine")
            case .stripeMRR:      return String(localized: "MRR Stripe")
            case .stripeTotal:    return String(localized: "Gain total Stripe")
            case .connector:      return String(localized: "Valeur d'un connecteur")
            }
        }

        var unit: String {
            switch self {
            case .macCPU, .macRAM, .deviceBattery, .deviceHumidity,
                 .claudeSession, .claudeWeekly: return "%"
            case .deviceTemp: return "°"
            case .stripeMRR, .stripeTotal, .connector: return ""
            }
        }

        var symbol: String {
            switch self {
            case .macCPU:         return "cpu"
            case .macRAM:         return "memorychip"
            case .deviceBattery:  return "battery.25"
            case .deviceTemp:     return "thermometer.medium"
            case .deviceHumidity: return "humidity.fill"
            case .claudeSession, .claudeWeekly: return "sparkles"
            case .stripeMRR:      return "creditcard"
            case .stripeTotal:    return "banknote"
            case .connector:      return "antenna.radiowaves.left.and.right"
            }
        }

        /// Vrai si la métrique se lit dans /api/stats de l'afficheur.
        var needsDeviceStats: Bool {
            switch self {
            case .deviceBattery, .deviceTemp, .deviceHumidity: return true
            default: return false
            }
        }
    }

    /// Sens du franchissement.
    enum Comparison: String, Codable, CaseIterable, Identifiable {
        case above, below
        var id: String { rawValue }
        var label: String {
            self == .above ? String(localized: "dépasse") : String(localized: "descend sous")
        }
        var symbol: String { self == .above ? ">" : "<" }
    }

    var id = UUID()
    var trigger: Trigger = .threshold
    var metric: Metric = .macCPU
    var connectorID: UUID?          // renseigné quand metric == .connector
    var comparison: Comparison = .above
    var threshold: Double = 90
    var scheduleMinutes: Int = 540  // minutes depuis minuit (540 = 09:00), pour trigger == .schedule
    var scheduleDays: Set<Int> = [] // 1=dimanche…7=samedi (Calendar.weekday) ; vide = tous les jours
    var message: String = ""        // vide → message généré ; « {value} » remplacé par la valeur
    var colorHex: String = "#FF5555"
    var icon: String = ""
    var sound: String = ""
    var indicator: Int = 0          // 0 = aucune LED, sinon 1…3
    var switchToApp: String = ""    // règle planifiée : app de la rotation à afficher au lieu de la notification
    var enabled: Bool = true

    /// Vrai si la valeur franchit le seuil.
    func isTriggered(value: Double) -> Bool {
        comparison == .above ? value > threshold : value < threshold
    }

    /// Message affiché sur la matrice (généré à partir de la métrique si non personnalisé).
    /// Pour une règle planifiée, la valeur n'a pas de sens : le message est utilisé tel quel.
    func renderedMessage(value: Double) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        if trigger == .schedule {
            return trimmed.isEmpty
                ? "\(String(localized: "Alerte planifiée")) \(Self.timeString(minutes: scheduleMinutes))"
                : trimmed
        }
        let formatted = Self.format(value) + metric.unit
        if trimmed.isEmpty {
            return "\(metric.label) \(formatted)"
        }
        return message.replacingOccurrences(of: "{value}", with: formatted)
    }

    /// Résumé lisible de la condition, ex. « CPU du Mac > 90% »
    /// ou « Tous les jours à 09:00 » pour une règle planifiée.
    func conditionSummary(connectorName: String? = nil) -> String {
        if trigger == .schedule {
            let time = Self.timeString(minutes: scheduleMinutes)
            if scheduleDays.isEmpty {
                return String(localized: "Tous les jours à \(time)")
            }
            let names = Self.weekOrder.filter { scheduleDays.contains($0) }
                .map { Self.dayShortNames[$0 - 1] }
            let list = names.joined(separator: ", ")
            return String(localized: "\(list.prefix(1).capitalized + list.dropFirst()) à \(time)")
        }
        let name = metric == .connector ? (connectorName ?? metric.label) : metric.label
        return "\(name) \(comparison.symbol) \(Self.format(threshold))\(metric.unit)"
    }

    /// Jours de la semaine dans l'ordre d'affichage français (lundi → dimanche), en weekday Calendar.
    static let weekOrder = [2, 3, 4, 5, 6, 7, 1]

    /// Noms courts indexés par weekday - 1 (1=dimanche…7=samedi).
    static let dayShortNames = ["dim", "lun", "mar", "mer", "jeu", "ven", "sam"]

    /// « 540 » → « 09:00 ».
    static func timeString(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    enum CodingKeys: String, CodingKey {
        case id, trigger, metric, connectorID, comparison, threshold
        case scheduleMinutes, scheduleDays, message, colorHex, icon, sound
        case indicator, switchToApp, enabled
    }

    init() {}

    /// Décodage tolérant : les champs ajoutés après coup (trigger, planification…)
    /// sont absents des règles déjà persistées → valeurs par défaut.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        trigger = try c.decodeIfPresent(Trigger.self, forKey: .trigger) ?? .threshold
        metric = try c.decodeIfPresent(Metric.self, forKey: .metric) ?? .macCPU
        connectorID = try c.decodeIfPresent(UUID.self, forKey: .connectorID)
        comparison = try c.decodeIfPresent(Comparison.self, forKey: .comparison) ?? .above
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 90
        scheduleMinutes = try c.decodeIfPresent(Int.self, forKey: .scheduleMinutes) ?? 540
        scheduleDays = try c.decodeIfPresent(Set<Int>.self, forKey: .scheduleDays) ?? []
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#FF5555"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        sound = try c.decodeIfPresent(String.self, forKey: .sound) ?? ""
        indicator = try c.decodeIfPresent(Int.self, forKey: .indicator) ?? 0
        switchToApp = try c.decodeIfPresent(String.self, forKey: .switchToApp) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// Extrait un nombre d'un texte de connecteur (« 1 234,5 € » → 1234.5).
    static func numericValue(from text: String) -> Double? {
        let filtered = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(filtered)
    }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
