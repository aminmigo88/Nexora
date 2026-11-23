import SwiftUI

enum AppTab: Hashable {
    case overview, lighting, ir, remotes, more
}

struct RootView: View {
    @Environment(Station.self) var station
    @Environment(\.scenePhase) var scenePhase
    @State var tab: AppTab = .overview

    var body: some View {
        TabView(selection: $tab) {
            OverviewView(tab: $tab)
                .tabItem { Label("Overview", systemImage: "house") }
                .tag(AppTab.overview)
            LightingView()
                .tabItem { Label("Lighting", systemImage: "lightbulb") }
                .tag(AppTab.lighting)
            IRFinderView()
                .tabItem { Label("IR Finder", systemImage: "dot.radiowaves.right") }
                .tag(AppTab.ir)
            RemotesView()
                .tabItem { Label("Remotes", systemImage: "av.remote") }
                .tag(AppTab.remotes)
            MoreView()
                .tabItem { Label("More", systemImage: "gearshape") }
                .tag(AppTab.more)
        }
        .tint(Theme.tealText)
        .overlay(alignment: .top) { ToastView() }
        .animation(.easeInOut(duration: 0.25), value: station.toast)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                station.appBecameActive()
            case .background:
                station.appWentToBackground()
            default:
                break
            }
        }
        .task {
            // When nothing answered, keep trying so the app reconnects by itself.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if station.link == .offline {
                    await station.refreshLink()
                }
            }
        }
    }
}
