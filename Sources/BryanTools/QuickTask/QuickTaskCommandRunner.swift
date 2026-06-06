import Darwin
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
    static let maxOutputBytes = 128 * 1024
    static let timeout: TimeInterval = 120

    static func run(_ command: String) async -> QuickTaskCommandResult {
        let execution = QuickTaskCommandExecution(
            command: command,
            maxOutputBytes: maxOutputBytes,
            timeout: timeout
        )
        return await withTaskCancellationHandler {
            await execution.run()
        } onCancel: {
            execution.cancel()
        }
    }
}

private final class QuickTaskCommandExecution: @unchecked Sendable {
    private let command: String
    private let maxOutputBytes: Int
    private let timeout: TimeInterval
    private let lock = NSLock()

    private var process: Process?
    private var outputPipe: Pipe?
    private var outputData = Data()
    private var outputWasTruncated = false
    private var didFinish = false
    private var didCancel = false
    private var didTimeout = false
    private var timeoutWorkItem: DispatchWorkItem?
    private var continuation: CheckedContinuation<QuickTaskCommandResult, Never>?

    init(command: String, maxOutputBytes: Int, timeout: TimeInterval) {
        self.command = command
        self.maxOutputBytes = maxOutputBytes
        self.timeout = timeout
    }

    func run() async -> QuickTaskCommandResult {
        await withCheckedContinuation { continuation in
            start(continuation)
        }
    }

    func cancel() {
        let runningProcess = lockedProcess(markCancelled: true, markTimedOut: false)
        terminate(runningProcess)
    }

    private func start(_ continuation: CheckedContinuation<QuickTaskCommandResult, Never>) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        lock.lock()
        self.process = process
        self.outputPipe = outputPipe
        self.continuation = continuation
        lock.unlock()

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.appendOutput(data)
        }

        process.terminationHandler = { [weak self] process in
            self?.finish(exitCode: process.terminationStatus)
        }

        do {
            try process.run()
            scheduleTimeout()
        } catch {
            finish(
                QuickTaskCommandResult(
                    command: command,
                    output: error.localizedDescription,
                    exitCode: nil,
                    isRunning: false
                )
            )
        }
    }

    private func scheduleTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            let runningProcess = self.lockedProcess(markCancelled: false, markTimedOut: true)
            self.terminate(runningProcess)
        }

        lock.lock()
        timeoutWorkItem = workItem
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func appendOutput(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        guard outputData.count < maxOutputBytes else {
            outputWasTruncated = true
            return
        }

        let remainingBytes = maxOutputBytes - outputData.count
        if data.count <= remainingBytes {
            outputData.append(data)
        } else {
            outputData.append(data.prefix(remainingBytes))
            outputWasTruncated = true
        }
    }

    private func lockedProcess(markCancelled: Bool, markTimedOut: Bool) -> Process? {
        lock.lock()
        if markCancelled {
            didCancel = true
        }
        if markTimedOut {
            didTimeout = true
        }
        let runningProcess = didFinish ? nil : process
        lock.unlock()
        return runningProcess
    }

    private func terminate(_ process: Process?) {
        guard let process, process.isRunning else {
            return
        }

        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func finish(exitCode: Int32?) {
        let output = currentOutput(exitCode: exitCode)
        finish(
            QuickTaskCommandResult(
                command: command,
                output: output,
                exitCode: exitCode,
                isRunning: false
            )
        )
    }

    private func finish(_ result: QuickTaskCommandResult) {
        let continuation: CheckedContinuation<QuickTaskCommandResult, Never>?
        let timeoutWorkItem: DispatchWorkItem?
        let outputPipe: Pipe?

        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        continuation = self.continuation
        timeoutWorkItem = self.timeoutWorkItem
        outputPipe = self.outputPipe
        self.continuation = nil
        self.timeoutWorkItem = nil
        self.outputPipe = nil
        self.process = nil
        lock.unlock()

        timeoutWorkItem?.cancel()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        try? outputPipe?.fileHandleForReading.close()
        try? outputPipe?.fileHandleForWriting.close()
        continuation?.resume(returning: result)
    }

    private func currentOutput(exitCode: Int32?) -> String {
        lock.lock()
        let data = outputData
        let wasTruncated = outputWasTruncated
        let timedOut = didTimeout
        let cancelled = didCancel
        lock.unlock()

        var output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .newlines)
            ?? ""

        if wasTruncated {
            output += output.isEmpty ? "Output truncated." : "\n\nOutput truncated."
        }
        if timedOut {
            output += output.isEmpty
                ? "Command timed out after \(Int(timeout)) seconds."
                : "\n\nCommand timed out after \(Int(timeout)) seconds."
        } else if cancelled, exitCode == nil {
            output += output.isEmpty ? "Command cancelled." : "\n\nCommand cancelled."
        }
        return output
    }
}
