import SwiftUI

@main
struct NexoraApp: App {
    @State private var station = Station()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(station)
                .environment(station.settings)
                .environment(station.history)
                .preferredColorScheme(.light)
        }
    }
}
