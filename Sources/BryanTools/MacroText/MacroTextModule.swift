import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class MacroTextModule: ObservableObject, ToolModule {
    static let shared = MacroTextModule(preferences: .load())

    let id = ToolIdentifier.macroText
    let displayName = ToolIdentifier.macroText.displayName
    let systemImage = "text.badge.plus"

    @Published private(set) var hotKey: AppHotKey
    @Published private(set) var replacements: [MacroTextReplacement]
    @Published private(set) var lastExpansion: String?
    @Published var lastErrorMessage: String?

    private enum HotKeyID {
        static let openConfig: HotKeyController.Identifier = 200
    }

    private let hotKeyController = HotKeyController()
    private var preferences: MacroTextPreferences
    private var eventTap: MacroTextEventTap?
    private var isRunning = false
    private lazy var configPanelController = MacroTextConfigPanelController(environment: self)

    private init(preferences: MacroTextPreferences) {
        self.preferences = preferences
        self.hotKey = preferences.hotKey
        self.replacements = preferences.replacements
    }

    func start() {
        isRunning = true
        registerHotKey()
        startEventTap()
    }

    func stop() {
        isRunning = false
        eventTap?.stop()
        eventTap = nil
        hotKeyController.unregisterAll()
    }

    func menuContent() -> AnyView {
        AnyView(MacroTextMenuContent(environment: self))
    }

    func settingsView() -> AnyView {
        AnyView(MacroTextSettingsView(environment: self))
    }

    func showConfig() {
        configPanelController.show()
    }

    func addOrUpdateReplacement(command rawCommand: String, replacement rawReplacement: String) {
        let command = normalizedCommand(rawCommand)
        let replacement = rawReplacement

        guard isValidCommand(command) else {
            lastErrorMessage = "MacroText command must start with / and contain no whitespace."
            return
        }
        guard !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastErrorMessage = "MacroText replacement cannot be empty."
            return
        }

        if let index = replacements.firstIndex(where: { $0.command == command }) {
            replacements[index].replacement = replacement
        } else {
            replacements.append(MacroTextReplacement(command: command, replacement: replacement))
        }
        replacements.sort { $0.command.localizedCaseInsensitiveCompare($1.command) == .orderedAscending }
        persistReplacements()
        lastErrorMessage = nil
    }

    func deleteReplacement(_ replacement: MacroTextReplacement) {
        replacements.removeAll { $0.id == replacement.id }
        persistReplacements()
    }

    func updateReplacement(_ replacement: MacroTextReplacement, command rawCommand: String, replacement rawReplacement: String) {
        let command = normalizedCommand(rawCommand)
        let replacementText = rawReplacement

        guard isValidCommand(command) else {
            lastErrorMessage = "MacroText command must start with / and contain no whitespace."
            return
        }
        guard !replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastErrorMessage = "MacroText replacement cannot be empty."
            return
        }
        guard replacements.contains(where: { $0.id == replacement.id }) else {
            lastErrorMessage = "MacroText replacement no longer exists."
            return
        }
        guard !replacements.contains(where: { $0.id != replacement.id && $0.command == command }) else {
            lastErrorMessage = "MacroText command already exists."
            return
        }

        replacements = replacements.map { item in
            guard item.id == replacement.id else {
                return item
            }
            return MacroTextReplacement(id: item.id, command: command, replacement: replacementText)
        }
        replacements.sort { $0.command.localizedCaseInsensitiveCompare($1.command) == .orderedAscending }
        persistReplacements()
        lastErrorMessage = nil
    }

    func updateHotKey(_ newHotKey: AppHotKey) {
        guard newHotKey.hasPrimaryModifier else {
            lastErrorMessage = "Shortcut must include Command, Control, or Option."
            return
        }

        let previousHotKey = hotKey
        do {
            if isRunning {
                try hotKeyController.register(newHotKey, identifier: HotKeyID.openConfig) { [weak self] in
                    self?.showConfig()
                }
            }
            hotKey = newHotKey
            preferences.hotKey = newHotKey
            preferences.save()
            lastErrorMessage = nil
        } catch {
            if isRunning {
                try? hotKeyController.register(previousHotKey, identifier: HotKeyID.openConfig) { [weak self] in
                    self?.showConfig()
                }
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func resetHotKey() {
        updateHotKey(.defaultMacroTextValue)
    }

    private func registerHotKey() {
        do {
            try hotKeyController.register(hotKey, identifier: HotKeyID.openConfig) { [weak self] in
                self?.showConfig()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func startEventTap() {
        guard AccessibilityPermissionService.ensurePermission(promptIfNeeded: true) else {
            lastErrorMessage = "Enable Accessibility permission for Bryan Tools to use MacroText."
            return
        }

        let tap = MacroTextEventTap(
            replacements: replacements,
            onMatch: { [weak self] replacement in
                Task { @MainActor in
                    self?.expand(replacement)
                }
            },
            onError: { [weak self] message in
                Task { @MainActor in
                    self?.lastErrorMessage = message
                }
            }
        )

        do {
            try tap.start()
            eventTap = tap
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func expand(_ replacement: MacroTextReplacement) {
        let resolvedReplacement = MacroTextTemplateRenderer.render(replacement.replacement)
        eventTap?.suppressEventsForExpansion()
        MacroTextTextInjector.replaceTypedCommand(
            commandLength: replacement.command.count,
            with: resolvedReplacement
        )
        lastExpansion = "\(replacement.command) -> \(resolvedReplacement)"
    }

    private func persistReplacements() {
        preferences.replacements = replacements
        preferences.save()
        eventTap?.updateReplacements(replacements)
    }

    private func normalizedCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    private func isValidCommand(_ command: String) -> Bool {
        command.hasPrefix("/")
            && command.count > 1
            && command.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}
