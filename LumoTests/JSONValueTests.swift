import Testing
import Foundation
@testable import Lumo

struct JSONValueTests {
    @Test func extractsNestedKey() {
        let data = Data(#"{"bitcoin":{"eur":42000}}"#.utf8)
        #expect(JSONValue.extract(path: "bitcoin.eur", from: data) == "42000")
    }

    @Test func extractsArrayWithBracketsOrDots() {
        let data = Data(#"{"data":[{"value":"45"}]}"#.utf8)
        #expect(JSONValue.extract(path: "data[0].value", from: data) == "45")
        #expect(JSONValue.extract(path: "data.0.value", from: data) == "45")
    }

    @Test func formatsIntegersWithoutDecimals() {
        let data = Data(#"{"v":42.0}"#.utf8)
        #expect(JSONValue.extract(path: "v", from: data) == "42")
    }

    @Test func formatsDecimalsToTwoPlaces() {
        let data = Data(#"{"v":1.5}"#.utf8)
        #expect(JSONValue.extract(path: "v", from: data) == "1.50")
    }

    @Test func missingPathReturnsNil() {
        let data = Data(#"{"a":1}"#.utf8)
        #expect(JSONValue.extract(path: "a.b", from: data) == nil)
    }

    @Test func emptyPathReturnsRootFragment() {
        let data = Data("123".utf8)
        #expect(JSONValue.extract(path: "", from: data) == "123")
    }

    @Test func handlesBooleans() {
        let data = Data(#"{"ok":true}"#.utf8)
        #expect(JSONValue.extract(path: "ok", from: data) == "true")
    }
}
