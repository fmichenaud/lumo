import Testing
import Foundation
@testable import Lumo

struct ConnectorTemplateTests {
    @Test func newTemplatesExist() {
        let titles = ConnectorTemplate.all.map(\.title)
        #expect(titles.contains("CI GitHub"))
        #expect(titles.contains("Plausible en direct"))
        #expect(titles.contains("Qualité de l'air"))
        #expect(titles.contains("Tempo EDF"))
        #expect(titles.contains("Abonnés YouTube"))
    }

    @Test func allTemplatesBuildValidConnectors() {
        for template in ConnectorTemplate.all {
            let c = template.build()
            #expect(c.template.contains("{value}"))
            #expect(c.intervalSeconds > 0)
            #expect(ConnectorTemplate.categoryOrder.contains(template.category))
        }
    }

    @Test func plausibleUsesBearerAndRawBody() {
        let c = ConnectorTemplate.all.first { $0.title == "Plausible en direct" }!.build()
        #expect(c.auth.kind == .bearer)
        #expect(c.jsonPath.isEmpty)   // la réponse est un nombre brut
        // JSONValue doit accepter un fragment JSON (nombre seul) avec un chemin vide.
        #expect(JSONValue.extract(path: "", from: Data("21".utf8)) == "21")
    }

    @Test func newPathsExtractFromSamplePayloads() {
        let tempo = #"{"dateJour":"2026-07-15","codeJour":1,"periode":"2025-2026","libCouleur":"Bleu"}"#
        #expect(JSONValue.extract(path: "libCouleur", from: Data(tempo.utf8)) == "Bleu")

        let air = #"{"current":{"time":"2026-07-15T18:00","european_aqi":47}}"#
        #expect(JSONValue.extract(path: "current.european_aqi", from: Data(air.utf8)) == "47")

        let ci = #"{"total_count":3,"workflow_runs":[{"conclusion":"success"}]}"#
        #expect(JSONValue.extract(path: "workflow_runs.0.conclusion", from: Data(ci.utf8)) == "success")

        let yt = #"{"items":[{"statistics":{"subscriberCount":"12345"}}]}"#
        #expect(JSONValue.extract(path: "items.0.statistics.subscriberCount", from: Data(yt.utf8)) == "12345")
    }
}
