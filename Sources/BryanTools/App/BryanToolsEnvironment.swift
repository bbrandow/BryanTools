import AppKit
import BryanToolsShared
import Foundation

@MainActor
final class BryanToolsEnvironment: ObservableObject {
    static let shared = BryanToolsEnvironment.makeShared()

    let clipboardHistory: ClipboardHistoryModule
    let colorPicker: ColorPickerModule
    let macroText: MacroTextModule
    let mouseMacro: MouseMacroModule
    let quickTask: QuickTaskModule
    let shotFloat: ShotFloatModule
    let screenOCR: ScreenOCRModule
    let alarm: AlarmModule
    let spotifyNowPlaying: SpotifyNowPlayingModule
    let trayCal: TrayCalModule
    let diskSpaceMonitor: DiskSpaceMonitorModule
    let utcHour: UTCHourModule
    let vehicleMotionCues: VehicleMotionCuesModule
    let updater: BryanToolsUpdater
    let autoStart: BryanToolsAutoStartController
    let tools: [any ToolModule]

    private lazy var settingsPanelController = BryanToolsSettingsPanelController(environment: self)

    private init(
        clipboardHistory: ClipboardHistoryModule,
        colorPicker: ColorPickerModule,
        macroText: MacroTextModule,
        mouseMacro: MouseMacroModule,
        quickTask: QuickTaskModule,
        shotFloat: ShotFloatModule,
        screenOCR: ScreenOCRModule,
        alarm: AlarmModule,
        spotifyNowPlaying: SpotifyNowPlayingModule,
        trayCal: TrayCalModule,
        diskSpaceMonitor: DiskSpaceMonitorModule,
        utcHour: UTCHourModule,
        vehicleMotionCues: VehicleMotionCuesModule,
        updater: BryanToolsUpdater,
        autoStart: BryanToolsAutoStartController
    ) {
        self.clipboardHistory = clipboardHistory
        self.colorPicker = colorPicker
        self.macroText = macroText
        self.mouseMacro = mouseMacro
        self.quickTask = quickTask
        self.shotFloat = shotFloat
        self.screenOCR = screenOCR
        self.alarm = alarm
        self.spotifyNowPlaying = spotifyNowPlaying
        self.trayCal = trayCal
        self.diskSpaceMonitor = diskSpaceMonitor
        self.utcHour = utcHour
        self.vehicleMotionCues = vehicleMotionCues
        self.updater = updater
        self.autoStart = autoStart
        self.tools = [
            clipboardHistory,
            colorPicker,
            macroText,
            mouseMacro,
            quickTask,
            shotFloat,
            screenOCR,
            alarm,
            spotifyNowPlaying,
            trayCal,
            diskSpaceMonitor,
            utcHour,
            vehicleMotionCues
        ]
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
        trayCal.setVehicleMotionCues(vehicleMotionCues)
        trayCal.setMouseMacro(mouseMacro)
        trayCal.setAlarm(alarm)
        trayCal.setSpotifyNowPlaying(spotifyNowPlaying)
    }

    func start() {
        autoStart.reconcile()
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
            mouseMacro: MouseMacroModule.shared,
            quickTask: QuickTaskModule.shared,
            shotFloat: ShotFloatModule.shared,
            screenOCR: ScreenOCRModule.shared,
            alarm: AlarmModule.shared,
            spotifyNowPlaying: SpotifyNowPlayingModule.shared,
            trayCal: TrayCalModule.shared,
            diskSpaceMonitor: DiskSpaceMonitorModule.shared,
            utcHour: UTCHourModule.shared,
            vehicleMotionCues: VehicleMotionCuesModule.shared,
            updater: BryanToolsUpdater(),
            autoStart: BryanToolsAutoStartController()
        )
    }
}
