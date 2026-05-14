import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        BryanToolsEnvironment.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        BryanToolsEnvironment.shared.stop()
    }
}

@main
struct BryanToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = BryanToolsEnvironment.shared

    var body: some Scene {
        MenuBarExtra("Bryan Tools", systemImage: "wrench.and.screwdriver") {
            BryanToolsMenuContent(environment: environment)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            BryanToolsSettingsView(environment: environment)
        }
    }
}
