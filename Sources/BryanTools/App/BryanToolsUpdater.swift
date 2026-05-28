import Foundation

@MainActor
final class BryanToolsUpdater: ObservableObject {
    @Published private(set) var isUpdating = false
    @Published private(set) var lastStatusMessage: String?
    @Published var lastErrorMessage: String?

    private var process: Process?
    private var outputData = Data()

    func runUpdate() {
        guard !isUpdating else {
            return
        }

        guard let scriptURL = updateScriptURL() else {
            lastErrorMessage = "Unable to find Scripts/update.sh."
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

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
            lastStatusMessage = "Running update..."
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    private func updateScriptURL() -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Users/bryan/BryanTools/Scripts/update.sh"),
            URL(fileURLWithPath: "/Users/bryan/code/BryanTools/Scripts/update.sh")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
