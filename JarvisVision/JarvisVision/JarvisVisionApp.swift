import SwiftUI

@main
struct JarvisVisionApp: App {
    @State private var windowManager = WindowManager()

    var body: some Scene {
        // Main Jarvis HUD — always visible, acts as the command center
        WindowGroup {
            ContentView()
                .environment(windowManager)
        }
        .windowStyle(.plain)
        .defaultSize(width: 500, height: 580)
        .windowResizability(.contentSize)

        // Chart windows — floating data visualizations
        WindowGroup("Chart", for: ChartWindowValue.self) { $value in
            if let value {
                ChartWindowView(windowId: value.windowId, payload: value.payload)
                    .environment(windowManager)
            }
        }
        .windowStyle(.plain)
        .defaultSize(width: 720, height: 520)
        .windowResizability(.contentMinSize)

        // Info card windows — markdown content panels
        WindowGroup("Info Card", for: InfoCardWindowValue.self) { $value in
            if let value {
                InfoCardView(windowId: value.windowId, payload: value.payload)
                    .environment(windowManager)
            }
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 480)
        .windowResizability(.contentMinSize)

        // Web panel windows — embedded web views
        WindowGroup("Web Panel", for: WebPanelWindowValue.self) { $value in
            if let value {
                WebPanelView(windowId: value.windowId, payload: value.payload)
                    .environment(windowManager)
            }
        }
        .windowStyle(.plain)
        .defaultSize(width: 960, height: 680)
        .windowResizability(.contentMinSize)
    }
}
