import SwiftUI

@main
struct SparkleApp: App {
    private var menubarIcon: Image {
        if let url = Bundle.main.url(forResource: "StatusIcon_18", withExtension: "png"),
           let nsImg = NSImage(contentsOf: url) {
            nsImg.isTemplate = true
            return Image(nsImage: nsImg)
        }
        return Image(systemName: "sparkles")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        MenuBarExtra {
            Button("Show Sparkle") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Quit Sparkle") {
                NSApp.terminate(nil)
            }
        } label: {
            menubarIcon
        }
    }
}
