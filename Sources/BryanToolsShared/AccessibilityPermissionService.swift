import ApplicationServices
import Foundation

public enum AccessibilityPermissionService {
    private static var hasRequestedAccessibilityThisLaunch = false

    public static func ensurePermission(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard promptIfNeeded, !hasRequestedAccessibilityThisLaunch else {
            return false
        }

        hasRequestedAccessibilityThisLaunch = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
