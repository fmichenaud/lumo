import SwiftUI

@main
struct LumoApp: App {
    @StateObject private var store = DeviceStore()
    @StateObject private var weatherStation = WeatherStation()
    @StateObject private var sceneStore = SceneStore()
    @StateObject private var liveApps = LiveAppsStation()
    @StateObject private var connectors = ConnectorsStation()

    var body: some Scene {
        WindowGroup("Lumo", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(weatherStation)
                .environmentObject(sceneStore)
                .environmentObject(liveApps)
                .environmentObject(connectors)
                .frame(minWidth: 940, minHeight: 620)
                .preferredColorScheme(.dark)
                .task { weatherStation.attach(store); liveApps.attach(store); connectors.attach(store) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))

        MenuBarExtra("Lumo", systemImage: "rays") {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(weatherStation)
        }
        .menuBarExtraStyle(.window)
    }
}
