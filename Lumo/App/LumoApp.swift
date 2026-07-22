import SwiftUI

@main
struct LumoApp: App {
    @State private var store = DeviceStore()
    @State private var weatherStation = WeatherStation()
    @State private var calendarStation = CalendarStation()
    @State private var sceneStore = SceneStore()
    @State private var liveApps = LiveAppsStation()
    @State private var connectors = ConnectorsStation()
    @State private var alerts = AlertsStation()
    @State private var nightMode = NightModeStation()
    @State private var pomodoro = PomodoroStation()
    @State private var gateway = NotificationGateway()
    @State private var poller = DevicePoller()

    var body: some Scene {
        WindowGroup("Lumo", id: "main") {
            RootView()
                .environment(store)
                .environment(weatherStation)
                .environment(calendarStation)
                .environment(sceneStore)
                .environment(liveApps)
                .environment(connectors)
                .environment(alerts)
                .environment(nightMode)
                .environment(pomodoro)
                .environment(gateway)
                .environment(poller)
                .frame(minWidth: 940, minHeight: 620)
                .preferredColorScheme(.dark)
                .task {
                    weatherStation.attach(store); liveApps.attach(store); calendarStation.attach(store)
                    connectors.attach(store); alerts.attach(store, connectors: connectors)
                    nightMode.attach(store); pomodoro.attach(store); gateway.attach(store)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))

        MenuBarExtra("Lumo", systemImage: "rays") {
            MenuBarView()
                .environment(store)
                .environment(weatherStation)
                .environment(connectors)
                .environment(pomodoro)
        }
        .menuBarExtraStyle(.window)
    }
}
