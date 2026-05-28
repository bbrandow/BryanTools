import Foundation

enum QuickTaskMode {
    case search
    case commandLine
}

struct QuickTaskCommandResult: Equatable, Sendable {
    let command: String
    let output: String
    let exitCode: Int32?
    let isRunning: Bool

    static func running(command: String) -> QuickTaskCommandResult {
        QuickTaskCommandResult(command: command, output: "", exitCode: nil, isRunning: true)
    }

    var exitCodeDescription: String {
        exitCode.map(String.init) ?? "unknown"
    }
}

enum QuickTaskCommandRunner {
    static func run(_ command: String) async -> QuickTaskCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSynchronously(command))
            }
        }
    }

    private static func runSynchronously(_ command: String) -> QuickTaskCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let outputQueue = DispatchQueue(label: "BryanTools.QuickTask.commandOutput")
        var outputData = Data()
        let outputGroup = DispatchGroup()
        outputGroup.enter()
        outputQueue.async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputGroup.leave()
        }

        do {
            try process.run()
            process.waitUntilExit()
            outputGroup.wait()
            let output = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .newlines)
                ?? ""

            return QuickTaskCommandResult(
                command: command,
                output: output,
                exitCode: process.terminationStatus,
                isRunning: false
            )
        } catch {
            try? outputPipe.fileHandleForWriting.close()
            outputGroup.wait()
            return QuickTaskCommandResult(
                command: command,
                output: error.localizedDescription,
                exitCode: nil,
                isRunning: false
            )
        }
    }
}
