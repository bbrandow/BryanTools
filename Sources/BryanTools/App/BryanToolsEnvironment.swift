import BryanToolsShared
import Foundation

@MainActor
final class BryanToolsEnvironment: ObservableObject {
    static let shared = BryanToolsEnvironment.makeShared()

    let clipboardHistory: ClipboardHistoryModule
    let colorPicker: ColorPickerModule
    let macroText: MacroTextModule
    let quickTask: QuickTaskModule
    let tools: [any ToolModule]

    private lazy var settingsPanelController = BryanToolsSettingsPanelController(environment: self)

    private init(
        clipboardHistory: ClipboardHistoryModule,
        colorPicker: ColorPickerModule,
        macroText: MacroTextModule,
        quickTask: QuickTaskModule
    ) {
        self.clipboardHistory = clipboardHistory
        self.colorPicker = colorPicker
        self.macroText = macroText
        self.quickTask = quickTask
        self.tools = [clipboardHistory, colorPicker, macroText, quickTask]
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
            quickTask: QuickTaskModule.shared
        )
    }
}
