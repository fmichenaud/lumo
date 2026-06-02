import Testing
import SwiftUI
@testable import Lumo

struct ColorTests {
    @Test func hexRoundTrip() {
        #expect(Color(hex: "#FFC400").hexString == "#FFC400")
        #expect(Color(hex: "FFC400").hexString == "#FFC400")
    }

    @Test func rgb24ToHex() {
        #expect(Color(rgb24: 0xFFC400).hexString == "#FFC400")
    }

    @Test func rgbArrayComponents() {
        #expect(Color(hex: "#FF0000").rgbArray == [255, 0, 0])
        #expect(Color(hex: "#00FF00").rgbArray == [0, 255, 0])
    }
}

struct WeatherConditionTests {
    @Test func mapsKnownCodes() {
        #expect(WeatherCondition.from(code: 0).iconID == "2282")   // ensoleillé
        #expect(WeatherCondition.from(code: 3).iconID == "91")     // couvert (statique)
        #expect(WeatherCondition.from(code: 61).label == "Pluie")
        #expect(WeatherCondition.from(code: 95).iconID == "11428") // orage
    }
}

struct NetworkUtilsTests {
    @Test func subnetBase() {
        #expect(NetworkUtils.subnetBase(from: "192.168.1.41") == "192.168.1")
        #expect(NetworkUtils.subnetBase(from: "invalide") == nil)
    }
}

struct SceneTests {
    @Test func appNameSanitized() {
        let scene = DisplayScene(name: "Mes Compteurs", text: "x", colorHex: "#FFFFFF", icon: "")
        #expect(scene.appName == "mes_compteurs")
    }

    @Test func payloadScrollsFully() {
        let payload = DisplayScene(name: "x", text: "salut", colorHex: "#FFFFFF", icon: "").payload()
        #expect(payload.repeatCount == 1)
        #expect(payload.text == "salut")
    }
}
