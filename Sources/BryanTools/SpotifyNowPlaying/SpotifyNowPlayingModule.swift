import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class SpotifyNowPlayingModule: ObservableObject, ToolModule {
    static let shared = SpotifyNowPlayingModule(preferences: .load())

    let id = ToolIdentifier.spotifyNowPlaying
    let displayName = ToolIdentifier.spotifyNowPlaying.displayName
    let systemImage = "music.note"

    @Published private(set) var isVisible: Bool
    @Published private(set) var snapshot = SpotifyNowPlayingSnapshot.notRunning
    @Published private(set) var lastErrorMessage: String?

    private var preferences: SpotifyNowPlayingPreferences
    private var pollTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var isRefreshInFlight = false
    private var isRunning = false
    private lazy var windowManager = SpotifyNowPlayingWindowManager(
        onDismiss: { [weak self] in
            self?.updateVisible(false)
        },
        onPositionChange: { [weak self] position in
            self?.savePosition(position)
        }
    )

    private init(preferences: SpotifyNowPlayingPreferences) {
        self.preferences = preferences
        self.isVisible = preferences.isVisible
    }

    var trayHelp: String {
        isVisible ? "Hide Spotify now playing" : "Show Spotify now playing"
    }

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        if isVisible {
            startShowing()
        }
    }

    func stop() {
        isRunning = false
        stopShowing()
    }

    func menuContent() -> AnyView {
        AnyView(EmptyView())
    }

    func settingsView() -> AnyView {
        AnyView(EmptyView())
    }

    func toggleVisible() {
        updateVisible(!isVisible)
    }

    func updateVisible(_ visible: Bool) {
        guard visible != isVisible else {
            return
        }
        isVisible = visible
        preferences.isVisible = visible
        preferences.save()

        guard isRunning else {
            return
        }
        if visible {
            startShowing()
        } else {
            stopShowing()
        }
    }

    private func startShowing() {
        windowManager.show(snapshot: snapshot, position: preferences.position)
        refresh()
        schedulePollTimer()
    }

    private func stopShowing() {
        pollTimer?.invalidate()
        pollTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshInFlight = false
        windowManager.close()
    }

    private func schedulePollTimer() {
        pollTimer?.invalidate()
        let timer = Timer(
            timeInterval: SpotifyNowPlayingPreferences.pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func refresh() {
        guard isRunning, isVisible, !isRefreshInFlight else {
            return
        }
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.spotify.client" && !$0.isTerminated
        }) else {
            apply(snapshot: .notRunning)
            return
        }

        isRefreshInFlight = true
        refreshTask = Task { [weak self] in
            let result = await SpotifyNowPlayingReader.read()
            guard let self, !Task.isCancelled else {
                return
            }
            self.isRefreshInFlight = false
            switch result {
            case .snapshot(let snapshot):
                self.apply(snapshot: snapshot)
            case .failure(let message):
                self.apply(snapshot: SpotifyNowPlayingSnapshot(
                    state: .unavailable,
                    message: message
                ))
            }
        }
    }

    private func apply(snapshot: SpotifyNowPlayingSnapshot) {
        self.snapshot = snapshot
        lastErrorMessage = snapshot.state == .unavailable ? snapshot.message : nil
        if isVisible {
            windowManager.show(snapshot: snapshot, position: preferences.position)
        }
    }

    private func savePosition(_ position: SpotifyNowPlayingPosition) {
        preferences.position = position
        preferences.save()
    }
}
