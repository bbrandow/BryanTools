import AppKit
import SwiftUI

struct BryanToolsMenuContent: View {
    @ObservedObject var environment: BryanToolsEnvironment

    var body: some View {
        ClipboardHistoryMenuContent(environment: environment.clipboardHistory)

        Divider()

        ColorPickerMenuContent(environment: environment.colorPicker)

        Divider()

        MacroTextMenuContent(environment: environment.macroText)

        Divider()

        QuickTaskMenuContent(environment: environment.quickTask)

        Divider()

        ShotFloatMenuContent(environment: environment.shotFloat)

        Divider()

        ScreenOCRMenuContent(environment: environment.screenOCR)

        Divider()

        Button {
            environment.showSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit Bryan Tools", systemImage: "power")
        }
    }
}
