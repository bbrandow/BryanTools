import AppKit
import Foundation

@MainActor
public enum PasteboardChangeSuppressor {
    private static var suppressedChangeCounts: Set<Int> = []

    public static func suppress(changeCount: Int = NSPasteboard.general.changeCount) {
        suppressedChangeCounts.insert(changeCount)
    }

    public static func shouldSuppress(changeCount: Int) -> Bool {
        suppressedChangeCounts.remove(changeCount) != nil
    }
}
