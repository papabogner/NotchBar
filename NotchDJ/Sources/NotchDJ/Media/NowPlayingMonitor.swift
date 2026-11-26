import AppKit
import Combine

/// Music and Spotify only, and only when one of them posts a playback change.
/// Nothing polls, so a quiet Mac stays idle.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var entry: NowPlaying?
    @Published private(set) var artwork: NSImage?

    func start() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let musicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: MediaSource.music.bundleID).isEmpty
        let spotifyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: MediaSource.spotify.bundleID).isEmpty
        Task.detached {
            let music = musicRunning ? PlayerScripts.nowPlaying(.music) : nil
            let spotify = spotifyRunning ? PlayerScripts.nowPlaying(.spotify) : nil
            let next = [music, spotify].compactMap { $0 }.first { $0.isPlaying } ?? music ?? spotify
            let art = Self.artworkData(for: next)
            await MainActor.run { [weak self] in
                self?.entry = next
                self?.artwork = art.flatMap { NSImage(data: $0) }
            }
        }
    }

    nonisolated private static func artworkData(for entry: NowPlaying?) -> Data? {
        guard let entry else { return nil }
        switch entry.source.kind {
        case .music:
            return PlayerScripts.musicArtwork()?.tiffRepresentation
        case .spotify:
            guard let url = PlayerScripts.spotifyArtworkURL() else { return nil }
            return try? Data(contentsOf: url)
        default:
            return nil
        }
    }
}
