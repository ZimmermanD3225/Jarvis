import SwiftUI

@main
struct JarvisVisionApp: App {
    @State private var windowManager = WindowManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(windowManager)
        }
        .windowStyle(.plain)

        WindowGroup("Chart", for: ChartWindowValue.self) { $value in
            if let value {
                ChartWindowView(windowId: value.windowId, payload: value.payload)
                    .environment(windowManager)
            }
        }
        .windowStyle(.plain)
        .defaultSize(width: 700, height: 500)

        WindowGroup("Info Card", for: InfoCardWindowValue.self) { $value in
            if let value {
                InfoCardView(windowId: value.windowId, payload: value.payload)
                    .environment(windowManager)
            }
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 450)

        WindowGroup("Web Panel", for: WebPanelWindowValue.self) { $value in
            if let value {
                WebPanelView(windowId: value.windowId, payload: value.payload)
                    .environment(windowManager)
            }
        }
        .windowStyle(.plain)
        .defaultSize(width: 900, height: 650)
    }
}
