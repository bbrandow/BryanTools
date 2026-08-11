import Foundation
import BryanToolsShared

enum SpotifyNowPlayingReadResult: Sendable {
    case snapshot(SpotifyNowPlayingSnapshot)
    case failure(String)
}

enum SpotifyNowPlayingReader {
    static func read() async -> SpotifyNowPlayingReadResult {
        await Task.detached(priority: .utility) {
            readSynchronously()
        }.value
    }

    private static func readSynchronously() -> SpotifyNowPlayingReadResult {
        let source = """
        tell application id "com.spotify.client"
            set playbackState to (player state as text)
            set trackName to ""
            set artistName to ""
            try
                set trackName to (name of current track as text)
                set artistName to (artist of current track as text)
            end try
            return {playbackState, trackName, artistName}
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            return .failure("Unable to create the Spotify playback query.")
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
            if code == -600 {
                return .snapshot(.notRunning)
            }
            if code == -1_743 {
                return .failure("Allow Bryan Tools to control Spotify in System Settings > Privacy & Security > Automation.")
            }
            let message = errorInfo["NSAppleScriptErrorMessage"] as? String
                ?? "Unable to read Spotify playback."
            return .failure(message)
        }

        let values = (1...descriptor.numberOfItems).map { index in
            descriptor.atIndex(index)?.stringValue ?? ""
        }
        return .snapshot(SpotifyNowPlayingDisplay.snapshot(scriptValues: values))
    }
}
