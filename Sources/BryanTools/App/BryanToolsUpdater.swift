import AppKit
import BryanToolsShared
import Foundation

@MainActor
final class BryanToolsUpdater: ObservableObject {
    @Published private(set) var isUpdating = false
    @Published private(set) var sourceRootPath: String
    @Published private(set) var lastStatusMessage: String?
    @Published var lastErrorMessage: String?

    private let defaults: UserDefaults
    private var process: Process?
    private var outputData = Data()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sourceRootPath = Self.loadSourceRootPath(defaults: defaults)
    }

    func runUpdate() {
        guard !isUpdating else {
            return
        }

        guard let resolution = updateScriptResolution() else {
            lastErrorMessage = "Unable to find Scripts/update.sh. Choose the BryanTools source folder in Settings."
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [resolution.scriptURL.path]
        process.currentDirectoryURL = resolution.sourceRoot

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        outputData = Data()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            Task { @MainActor in
                self?.outputData.append(data)
                self?.lastStatusMessage = String(data: self?.outputData ?? Data(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        process.terminationHandler = { [weak self, weak pipe] process in
            pipe?.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.isUpdating = false
                self.process = nil
                if process.terminationStatus == 0 {
                    self.lastErrorMessage = nil
                    self.lastStatusMessage = "Update started."
                } else {
                    let output = String(data: self.outputData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastErrorMessage = output?.isEmpty == false
                        ? output
                        : "Update failed with status \(process.terminationStatus)."
                }
            }
        }

        do {
            try process.run()
            self.process = process
            isUpdating = true
            lastErrorMessage = nil
            lastStatusMessage = "Running update from \(resolution.sourceRoot.path)..."
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func chooseSourceRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose BryanTools Source Folder"
        panel.message = "Choose the BryanTools checkout that contains Scripts/update.sh."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: sourceRootPath, isDirectory: true)

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }
        updateSourceRoot(url)
    }

    func resetSourceRoot() {
        defaults.removeObject(forKey: BryanToolsUpdateScriptResolver.sourceRootDefaultsKey)
        sourceRootPath = Self.loadSourceRootPath(defaults: defaults)
        lastErrorMessage = nil
    }

    func updateSourceRoot(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        let scriptURL = standardizedURL.appendingPathComponent("Scripts/update.sh")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scriptURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            lastErrorMessage = "Selected folder does not contain Scripts/update.sh."
            return
        }

        defaults.set(standardizedURL.path, forKey: BryanToolsUpdateScriptResolver.sourceRootDefaultsKey)
        sourceRootPath = standardizedURL.path
        lastErrorMessage = nil
        lastStatusMessage = "Updater source set to \(standardizedURL.path)."
    }

    private func updateScriptResolution() -> BryanToolsUpdateScriptResolution? {
        let configuredSourceRoot = configuredSourceRootURL(defaults: defaults)
        if let resolution = BryanToolsUpdateScriptResolver.resolve(configuredSourceRoot: configuredSourceRoot) {
            if sourceRootPath != resolution.sourceRoot.path {
                sourceRootPath = resolution.sourceRoot.path
            }
            return resolution
        }
        return nil
    }

    private static func loadSourceRootPath(defaults: UserDefaults) -> String {
        let configuredSourceRoot = configuredSourceRootURL(defaults: defaults)
        return BryanToolsUpdateScriptResolver.resolve(configuredSourceRoot: configuredSourceRoot)?.sourceRoot.path
            ?? configuredSourceRoot?.path
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("code/BryanTools", isDirectory: true).path
    }

    private static func configuredSourceRootURL(defaults: UserDefaults) -> URL? {
        guard let path = defaults.string(forKey: BryanToolsUpdateScriptResolver.sourceRootDefaultsKey),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func configuredSourceRootURL(defaults: UserDefaults) -> URL? {
        Self.configuredSourceRootURL(defaults: defaults)
    }
}
