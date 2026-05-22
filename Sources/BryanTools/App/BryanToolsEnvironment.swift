import AppKit
import BryanToolsShared
import Foundation

@MainActor
final class BryanToolsEnvironment: ObservableObject {
    static let shared = BryanToolsEnvironment.makeShared()

    let clipboardHistory: ClipboardHistoryModule
    let colorPicker: ColorPickerModule
    let macroText: MacroTextModule
    let quickTask: QuickTaskModule
    let shotFloat: ShotFloatModule
    let screenOCR: ScreenOCRModule
    let trayCal: TrayCalModule
    let diskSpaceMonitor: DiskSpaceMonitorModule
    let tools: [any ToolModule]

    private lazy var settingsPanelController = BryanToolsSettingsPanelController(environment: self)

    private init(
        clipboardHistory: ClipboardHistoryModule,
        colorPicker: ColorPickerModule,
        macroText: MacroTextModule,
        quickTask: QuickTaskModule,
        shotFloat: ShotFloatModule,
        screenOCR: ScreenOCRModule,
        trayCal: TrayCalModule,
        diskSpaceMonitor: DiskSpaceMonitorModule
    ) {
        self.clipboardHistory = clipboardHistory
        self.colorPicker = colorPicker
        self.macroText = macroText
        self.quickTask = quickTask
        self.shotFloat = shotFloat
        self.screenOCR = screenOCR
        self.trayCal = trayCal
        self.diskSpaceMonitor = diskSpaceMonitor
        self.tools = [clipboardHistory, colorPicker, macroText, quickTask, shotFloat, screenOCR, trayCal, diskSpaceMonitor]
        screenOCR.setTextOutputHandler { text in
            try clipboardHistory.copyTextToClipboardAndHistory(text)
        }
        trayCal.setActionHandlers(
            showSettings: { [weak self] in
                self?.showSettings()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
    }

    func start() {
        for tool in tools {
            tool.start()
        }
    }

    func stop() {
        for tool in tools.reversed() {
            tool.stop()
        }
    }

    func showSettings() {
        settingsPanelController.show()
    }

    private static func makeShared() -> BryanToolsEnvironment {
        BryanToolsEnvironment(
            clipboardHistory: ClipboardHistoryModule.shared,
            colorPicker: ColorPickerModule.shared,
            macroText: MacroTextModule.shared,
            quickTask: QuickTaskModule.shared,
            shotFloat: ShotFloatModule.shared,
            screenOCR: ScreenOCRModule.shared,
            trayCal: TrayCalModule.shared,
            diskSpaceMonitor: DiskSpaceMonitorModule.shared
        )
    }
}
