import AppKit
import BryanToolsShared
import ClipboardHistoryCore
import Foundation

@MainActor
final class PasteboardMonitor {
    var isPaused = false

    private let store: ClipStore
    private let onCapture: (ClipRecord) -> Void
    private let onError: (Error) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private var suppressedChangeCount: Int?

    init(
        store: ClipStore,
        onCapture: @escaping (ClipRecord) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.store = store
        self.onCapture = onCapture
        self.onError = onError
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else {
            return
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func noteInternalPasteboardWrite(changeCount: Int = NSPasteboard.general.changeCount) {
        PasteboardChangeSuppressor.suppress(changeCount: changeCount)
        suppressedChangeCount = changeCount
        lastChangeCount = changeCount
    }

    func performIgnoringPasteboardChanges<T>(_ body: () throws -> T) rethrows -> T {
        let wasRunning = timer != nil
        stop()

        do {
            let result = try body()
            noteInternalPasteboardWrite()
            if wasRunning {
                start()
            }
            return result
        } catch {
            noteInternalPasteboardWrite()
            if wasRunning {
                start()
            }
            throw error
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        let changeCount = pasteboard.changeCount
        lastChangeCount = changeCount

        if suppressedChangeCount == changeCount || PasteboardChangeSuppressor.shouldSuppress(changeCount: changeCount) {
            suppressedChangeCount = nil
            return
        }

        guard !isPaused else {
            return
        }

        do {
            if let record = try store.captureCurrentPasteboard(
                pasteboard,
                sourceApplication: NSWorkspace.shared.frontmostApplication
            ) {
                onCapture(record)
            }
        } catch {
            onError(error)
        }
    }
}
