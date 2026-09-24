import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        BryanToolsEnvironment.shared.start()
        DispatchQueue.main.async {
            BryanToolsEnvironment.shared.autoStart.reconcile()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        BryanToolsEnvironment.shared.stop()
    }
}

@main
@MainActor
enum BryanToolsLauncher {
    static func main() {
        // SceneBuilder cannot conditionally apply macOS 15 scene policies.
        if #available(macOS 15.0, *) {
            BryanToolsApp.main()
        } else {
            BryanToolsLegacyApp.main()
        }
    }
}

@available(macOS 15.0, *)
struct BryanToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = BryanToolsEnvironment.shared

    var body: some Scene {
        Settings {
            BryanToolsSettingsView(environment: environment)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

private struct BryanToolsLegacyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = BryanToolsEnvironment.shared

    var body: some Scene {
        Settings {
            BryanToolsSettingsView(environment: environment)
        }
    }
}
