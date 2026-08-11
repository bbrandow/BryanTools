import Foundation

public struct SpotifyNowPlayingPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct SpotifyNowPlayingPreferences: Equatable, Sendable {
    public static let defaultVisible = false
    public static let pollInterval: TimeInterval = 3

    public var isVisible: Bool
    public var position: SpotifyNowPlayingPosition?

    public init(isVisible: Bool = defaultVisible, position: SpotifyNowPlayingPosition? = nil) {
        self.isVisible = isVisible
        self.position = position
    }

    public static func load(defaults: UserDefaults = .standard) -> SpotifyNowPlayingPreferences {
        let isVisible = defaults.object(forKey: Key.isVisible) == nil
            ? defaultVisible
            : defaults.bool(forKey: Key.isVisible)
        let position: SpotifyNowPlayingPosition?
        if defaults.object(forKey: Key.positionX) != nil,
           defaults.object(forKey: Key.positionY) != nil {
            position = SpotifyNowPlayingPosition(
                x: defaults.double(forKey: Key.positionX),
                y: defaults.double(forKey: Key.positionY)
            )
        } else {
            position = nil
        }
        return SpotifyNowPlayingPreferences(isVisible: isVisible, position: position)
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(isVisible, forKey: Key.isVisible)
        if let position {
            defaults.set(position.x, forKey: Key.positionX)
            defaults.set(position.y, forKey: Key.positionY)
        } else {
            defaults.removeObject(forKey: Key.positionX)
            defaults.removeObject(forKey: Key.positionY)
        }
    }

    private enum Key {
        static let isVisible = "spotifyNowPlaying.isVisible"
        static let positionX = "spotifyNowPlaying.position.x"
        static let positionY = "spotifyNowPlaying.position.y"
    }
}

public enum SpotifyPlaybackState: String, Equatable, Sendable {
    case playing
    case paused
    case stopped
    case notRunning
    case unavailable
}

public struct SpotifyNowPlayingSnapshot: Equatable, Sendable {
    public var state: SpotifyPlaybackState
    public var title: String
    public var artist: String
    public var message: String?

    public init(
        state: SpotifyPlaybackState,
        title: String = "",
        artist: String = "",
        message: String? = nil
    ) {
        self.state = state
        self.title = title
        self.artist = artist
        self.message = message
    }

    public static let notRunning = SpotifyNowPlayingSnapshot(state: .notRunning)
}

public enum SpotifyNowPlayingDisplay {
    public static func snapshot(scriptValues: [String]) -> SpotifyNowPlayingSnapshot {
        let values = scriptValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let stateText = values.first?.lowercased() ?? ""
        let title = values.indices.contains(1) ? values[1] : ""
        let artist = values.indices.contains(2) ? values[2] : ""

        switch stateText {
        case "playing":
            return SpotifyNowPlayingSnapshot(state: .playing, title: title, artist: artist)
        case "paused":
            return SpotifyNowPlayingSnapshot(state: .paused, title: title, artist: artist)
        case "stopped":
            return SpotifyNowPlayingSnapshot(state: .stopped)
        case "notrunning":
            return .notRunning
        default:
            return SpotifyNowPlayingSnapshot(
                state: .unavailable,
                message: "Unable to read Spotify playback."
            )
        }
    }

    public static func primaryText(for snapshot: SpotifyNowPlayingSnapshot) -> String {
        switch snapshot.state {
        case .playing, .paused:
            return snapshot.title.isEmpty ? "Unknown track" : snapshot.title
        case .stopped:
            return "Nothing playing"
        case .notRunning:
            return "Spotify isn't running"
        case .unavailable:
            return "Spotify access unavailable"
        }
    }

    public static func secondaryText(for snapshot: SpotifyNowPlayingSnapshot) -> String {
        switch snapshot.state {
        case .playing:
            return snapshot.artist.isEmpty ? "Playing" : snapshot.artist
        case .paused:
            return snapshot.artist.isEmpty ? "Paused" : "\(snapshot.artist) - Paused"
        case .stopped:
            return "Spotify"
        case .notRunning:
            return "Open Spotify to see the current track"
        case .unavailable:
            return snapshot.message ?? "Allow Bryan Tools to control Spotify"
        }
    }
}
