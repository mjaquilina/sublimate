import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        DatabaseManager.shared.backupDatabase()
    }
}

@main
struct SublimateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var databaseInitialized = false
    @State private var initializationError: Error?

    init() {
        // Activate the app and bring windows to front
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Initialize database on app launch
        do {
            try DatabaseManager.shared.initialize()
            print("Database initialized successfully")
        } catch {
            print("Failed to initialize database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: Constants.UI.minimumWindowWidth,
                       minHeight: Constants.UI.minimumWindowHeight)
        }
        .commands {
            NavigationCommands()
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("About Sublimate") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "Sublimate",
                            NSApplication.AboutPanelOptionKey.applicationVersion: Constants.appVersion,
                            NSApplication.AboutPanelOptionKey.version: "",
                            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2024"
                        ]
                    )
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}
