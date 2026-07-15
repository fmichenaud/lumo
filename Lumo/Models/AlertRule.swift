import Foundation

/// Une règle d'alerte : surveille une métrique et déclenche une notification
/// (et éventuellement une LED témoin) quand la valeur franchit un seuil.
struct AlertRule: Identifiable, Codable, Hashable {

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
    var metric: Metric = .macCPU
    var connectorID: UUID?          // renseigné quand metric == .connector
    var comparison: Comparison = .above
    var threshold: Double = 90
    var message: String = ""        // vide → message généré ; « {value} » remplacé par la valeur
    var colorHex: String = "#FF5555"
    var icon: String = ""
    var sound: String = ""
    var indicator: Int = 0          // 0 = aucune LED, sinon 1…3
    var enabled: Bool = true

    /// Vrai si la valeur franchit le seuil.
    func isTriggered(value: Double) -> Bool {
        comparison == .above ? value > threshold : value < threshold
    }

    /// Message affiché sur la matrice (généré à partir de la métrique si non personnalisé).
    func renderedMessage(value: Double) -> String {
        let formatted = Self.format(value) + metric.unit
        if message.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(metric.label) \(formatted)"
        }
        return message.replacingOccurrences(of: "{value}", with: formatted)
    }

    /// Résumé lisible de la condition, ex. « CPU du Mac > 90% ».
    func conditionSummary(connectorName: String? = nil) -> String {
        let name = metric == .connector ? (connectorName ?? metric.label) : metric.label
        return "\(name) \(comparison.symbol) \(Self.format(threshold))\(metric.unit)"
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
