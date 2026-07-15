import Testing
import Foundation
@testable import Lumo

// MARK: - Query string

struct GatewayQueryTests {
    @Test func decodesPercentEncoding() {
        let params = NotificationGateway.parseQuery("text=Coucou%20toi&color=%23FF5555")
        #expect(params["text"] == "Coucou toi")
        #expect(params["color"] == "#FF5555")
    }

    @Test func plusMeansSpace() {
        #expect(NotificationGateway.parseQuery("text=Salut+le+monde")["text"] == "Salut le monde")
    }

    @Test func keyWithoutValueAndEmptyPairs() {
        let params = NotificationGateway.parseQuery("hold&&text=ok&=orphan")
        #expect(params["hold"] == "")
        #expect(params["text"] == "ok")
        #expect(params.count == 2)
    }

    @Test func malformedPercentEncodingIgnored() {
        let params = NotificationGateway.parseQuery("text=ok&bad=%ZZ")
        #expect(params["text"] == "ok")
        #expect(params["bad"] == nil)
    }
}

// MARK: - Construction du payload

struct GatewayPayloadTests {
    @Test func fromParamsMinimal() throws {
        let payload = try #require(NotificationGateway.payload(fromParams: ["text": "Coucou"]))
        #expect(payload.text == "Coucou")
        #expect(payload.wakeup == true)
        #expect(payload.color == nil)
        #expect(payload.hold == nil)
    }

    @Test func fromParamsComplete() throws {
        let payload = try #require(NotificationGateway.payload(fromParams: [
            "text": "Build OK", "title": "CI", "color": "#3DD68C",
            "icon": "1234", "hold": "true", "duration": "12",
        ]))
        #expect(payload.text == "CI : Build OK")
        #expect(payload.color == "#3DD68C")
        #expect(payload.icon == "1234")
        #expect(payload.hold == true)
        #expect(payload.duration == 12)
    }

    @Test func fromParamsRequiresText() {
        #expect(NotificationGateway.payload(fromParams: [:]) == nil)
        #expect(NotificationGateway.payload(fromParams: ["text": ""]) == nil)
        #expect(NotificationGateway.payload(fromParams: ["title": "Seul"]) == nil)
    }

    @Test func holdVariants() {
        #expect(NotificationGateway.payload(fromParams: ["text": "x", "hold": "1"])?.hold == true)
        #expect(NotificationGateway.payload(fromParams: ["text": "x", "hold": "false"])?.hold == false)
    }

    @Test func fromJSONMinimal() throws {
        let payload = try #require(NotificationGateway.payload(fromJSON: ["text": "Coucou"]))
        #expect(payload.text == "Coucou")
        #expect(payload.wakeup == true)
    }

    @Test func fromJSONComplete() throws {
        let payload = try #require(NotificationGateway.payload(fromJSON: [
            "text": "42 %", "title": "Batterie", "color": "#FFC400",
            "icon": "battery", "hold": true, "duration": 8,
        ]))
        #expect(payload.text == "Batterie : 42 %")
        #expect(payload.color == "#FFC400")
        #expect(payload.icon == "battery")
        #expect(payload.hold == true)
        #expect(payload.duration == 8)
    }

    @Test func fromJSONInvalid() {
        #expect(NotificationGateway.payload(fromJSON: [:]) == nil)
        #expect(NotificationGateway.payload(fromJSON: ["text": 42]) == nil)
        #expect(NotificationGateway.payload(fromJSON: ["title": "sans texte"]) == nil)
    }
}

// MARK: - Parsing HTTP

struct GatewayHTTPTests {
    private func request(_ raw: String) -> Data { Data(raw.utf8) }

    private func status(of response: Data) -> String {
        String(decoding: response, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
    }

    @Test func postNotifyValid() {
        let body = ##"{"text":"Coucou","color":"#FF5555"}"##
        let raw = request("POST /notify HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        let (response, payload) = NotificationGateway.handleRequest(raw)
        #expect(status(of: response) == "HTTP/1.1 200 OK")
        #expect(payload?.text == "Coucou")
        #expect(payload?.color == "#FF5555")
    }

    @Test func postNotifyInvalidJSON() {
        let raw = request("POST /notify HTTP/1.1\r\nContent-Length: 8\r\n\r\npas json")
        let (response, payload) = NotificationGateway.handleRequest(raw)
        #expect(status(of: response) == "HTTP/1.1 400 Bad Request")
        #expect(payload == nil)
    }

    @Test func getNotifyWithQuery() {
        let raw = request("GET /notify?text=Coucou&color=%23FF5555 HTTP/1.1\r\n\r\n")
        let (response, payload) = NotificationGateway.handleRequest(raw)
        #expect(status(of: response) == "HTTP/1.1 200 OK")
        #expect(payload?.text == "Coucou")
        #expect(payload?.color == "#FF5555")
    }

    @Test func getNotifyWithoutText() {
        let raw = request("GET /notify?color=%23FF5555 HTTP/1.1\r\n\r\n")
        let (response, payload) = NotificationGateway.handleRequest(raw)
        #expect(status(of: response) == "HTTP/1.1 400 Bad Request")
        #expect(payload == nil)
    }

    @Test func unknownPathIs404() {
        let raw = request("GET /autre HTTP/1.1\r\n\r\n")
        let (response, payload) = NotificationGateway.handleRequest(raw)
        #expect(status(of: response) == "HTTP/1.1 404 Not Found")
        #expect(payload == nil)
    }

    @Test func garbageIs400() {
        let (response, payload) = NotificationGateway.handleRequest(Data("n'importe quoi\r\n\r\n".utf8))
        #expect(status(of: response) == "HTTP/1.1 400 Bad Request")
        #expect(payload == nil)
    }

    @Test func requestCompletionTracksContentLength() {
        let partial = Data("POST /notify HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345".utf8)
        #expect(!NotificationGateway.requestIsComplete(partial))
        let full = Data("POST /notify HTTP/1.1\r\nContent-Length: 10\r\n\r\n1234567890".utf8)
        #expect(NotificationGateway.requestIsComplete(full))
        let noBody = Data("GET /notify?text=a HTTP/1.1\r\n\r\n".utf8)
        #expect(NotificationGateway.requestIsComplete(noBody))
        #expect(!NotificationGateway.requestIsComplete(Data("GET /notify".utf8)))
    }

    @Test func contentLengthParsing() {
        #expect(NotificationGateway.contentLength(inHead: "POST / HTTP/1.1\r\ncontent-length: 42\r\nHost: x") == 42)
        #expect(NotificationGateway.contentLength(inHead: "GET / HTTP/1.1\r\nHost: x") == 0)
    }
}

// MARK: - Schéma d'URL et serveur réel

@MainActor
struct GatewayLiveTests {
    private static func makeGateway() -> NotificationGateway {
        let suite = "lumo.tests.gateway"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return NotificationGateway(defaults: defaults)
    }

    @Test func urlSchemeNotifyIsHandledAndOthersIgnored() {
        let gateway = Self.makeGateway()
        gateway.handle(url: URL(string: "lumo://oauth?code=abc")!)
        #expect(gateway.receivedCount == 0)
        gateway.handle(url: URL(string: "lumo://notify?text=Salut&title=Test&color=%23FF5555")!)
        #expect(gateway.receivedCount == 1)
        #expect(gateway.lastMessage == "Test : Salut")
        gateway.handle(url: URL(string: "lumo://notify?color=%23FF5555")!) // pas de texte
        #expect(gateway.receivedCount == 1)
    }

    /// Intégration : vrai listener sur un port libre + vraies requêtes URLSession en loopback.
    @Test func realServerRoundTrip() async throws {
        let gateway = Self.makeGateway()
        gateway.setPort(Int.random(in: 20000..<60000))
        gateway.setEnabled(true)
        defer { gateway.setEnabled(false) }

        for _ in 0..<100 where !gateway.isRunning {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try #require(gateway.isRunning, "Le listener n'a pas démarré (port \(gateway.port))")

        // POST /notify avec JSON valide → 200 "OK".
        var post = URLRequest(url: URL(string: "http://127.0.0.1:\(gateway.port)/notify")!)
        post.httpMethod = "POST"
        post.httpBody = Data(#"{"text":"test intégration"}"#.utf8)
        let (data, response) = try await URLSession.shared.data(for: post)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "OK")

        // GET /notify?text=… → 200.
        let getURL = URL(string: "http://127.0.0.1:\(gateway.port)/notify?text=Coucou&color=%23FF5555")!
        let (_, getResponse) = try await URLSession.shared.data(from: getURL)
        #expect((getResponse as? HTTPURLResponse)?.statusCode == 200)

        // Chemin inconnu → 404 ; JSON invalide → 400.
        let (_, notFound) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(gateway.port)/autre")!)
        #expect((notFound as? HTTPURLResponse)?.statusCode == 404)
        var bad = URLRequest(url: URL(string: "http://127.0.0.1:\(gateway.port)/notify")!)
        bad.httpMethod = "POST"
        bad.httpBody = Data("pas du json".utf8)
        let (_, badResponse) = try await URLSession.shared.data(for: bad)
        #expect((badResponse as? HTTPURLResponse)?.statusCode == 400)

        // Les deux messages valides ont été publiés (la livraison passe par le MainActor).
        for _ in 0..<100 where gateway.receivedCount < 2 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(gateway.receivedCount == 2)
        #expect(gateway.lastMessage == "Coucou")
    }
}
