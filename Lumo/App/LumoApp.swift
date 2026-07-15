import SwiftUI

@main
struct LumoApp: App {
    @StateObject private var store = DeviceStore()
    @StateObject private var weatherStation = WeatherStation()
    @StateObject private var calendarStation = CalendarStation()
    @StateObject private var sceneStore = SceneStore()
    @StateObject private var liveApps = LiveAppsStation()
    @StateObject private var connectors = ConnectorsStation()
    @StateObject private var alerts = AlertsStation()
    @StateObject private var nightMode = NightModeStation()
    @StateObject private var pomodoro = PomodoroStation()

    var body: some Scene {
        WindowGroup("Lumo", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(weatherStation)
                .environmentObject(calendarStation)
                .environmentObject(sceneStore)
                .environmentObject(liveApps)
                .environmentObject(connectors)
                .environmentObject(alerts)
                .environmentObject(nightMode)
                .environmentObject(pomodoro)
                .frame(minWidth: 940, minHeight: 620)
                .preferredColorScheme(.dark)
                .task {
                    weatherStation.attach(store); liveApps.attach(store); calendarStation.attach(store)
                    connectors.attach(store); alerts.attach(store, connectors: connectors)
                    nightMode.attach(store); pomodoro.attach(store)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))

        MenuBarExtra("Lumo", systemImage: "rays") {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(weatherStation)
                .environmentObject(connectors)
                .environmentObject(pomodoro)
        }
        .menuBarExtraStyle(.window)
    }
}
