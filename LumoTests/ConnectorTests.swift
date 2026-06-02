import Testing
@testable import Lumo

struct ConnectorTests {
    @Test func appNameIsSanitized() {
        #expect(Connector(name: "Bitcoin").appName == "bitcoin")
        #expect(Connector(name: "Mon API Perso").appName == "mon_api_perso")
    }

    @Test func emptyNameFallsBackToPrefix() {
        #expect(Connector().appName.hasPrefix("api_"))
    }

    @Test func renderedTextReplacesPlaceholder() {
        let c = Connector(template: "BTC {value}€")
        #expect(c.renderedText(value: "42000") == "BTC 42000€")
    }

    @Test func bearerHeader() {
        var c = Connector(url: "https://x")
        c.auth.kind = .bearer
        c.auth.bearerToken = "tok123"
        #expect(c.requestHeaders()["Authorization"] == "Bearer tok123")
    }

    @Test func apiKeyHeader() {
        var c = Connector()
        c.auth.kind = .apiKey
        c.auth.headerName = "X-API-Key"
        c.auth.apiKey = "secret"
        #expect(c.requestHeaders()["X-API-Key"] == "secret")
    }

    @Test func extraHeadersAreParsed() {
        var c = Connector()
        c.extraHeadersText = "Accept: application/json\nX-Custom: hello"
        let headers = c.requestHeaders()
        #expect(headers["Accept"] == "application/json")
        #expect(headers["X-Custom"] == "hello")
    }

    @Test func noneAuthAddsNoAuthHeader() {
        let c = Connector()
        #expect(c.requestHeaders()["Authorization"] == nil)
    }
}
