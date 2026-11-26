import AppKit
import Combine

/// Music and Spotify only, and only when one of them posts a playback change.
/// Nothing polls, so a quiet Mac stays idle. Artwork is fetched once per track.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var entry: NowPlaying?
    @Published private(set) var artwork: NSImage?

    /// Players that can't be scripted get the system media keys when this returns true.
    var mediaKeysAllowed: @MainActor () -> Bool = { false }

    private var artworkKey: String?
    private var refreshing = false
    private var refreshAgain = false
    private var started = false
    private let isPreview: Bool

    init(preview: NowPlaying? = nil, artwork: NSImage? = nil) {
        isPreview = preview != nil
        entry = preview
        self.artwork = artwork
    }

    func start() {
        guard !isPreview, !started else { return }
        started = true
        let center = DistributedNotificationCenter.default()
        let monitor = self
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { monitor.refresh() }
            }
        }
        refresh()
    }

    /// Reads Music and Spotify off the main thread. Calls during a read are folded into one more read.
    func refresh() {
        guard !isPreview else { return }
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        let musicRunning = MediaSource.music.isRunning
        let spotifyRunning = MediaSource.spotify.isRunning
        let knownKey = artworkKey
        let monitor = self
        Task.detached(priority: .userInitiated) {
            let music = musicRunning ? PlayerScripts.nowPlaying(.music) : nil
            let spotify = spotifyRunning ? PlayerScripts.nowPlaying(.spotify) : nil
            let next = [music, spotify].compactMap { $0 }.first { $0.isPlaying } ?? music ?? spotify
            let key = next.map { "\($0.source.bundleID)|\($0.trackID)" }
            let art = key != nil && key != knownKey ? Self.artworkData(for: next) : nil
            await MainActor.run {
                monitor.apply(next, key: key, artwork: art)
            }
        }
    }

    // MARK: Transport

    func togglePlay() { send(.toggle) }
    func next() { send(.next) }
    func previous() { send(.previous) }

    /// Media keys for whatever macOS treats as the current player, when nothing scriptable is playing.
    func sendMediaKey(_ command: PlayerScripts.Command) {
        guard !isPreview, mediaKeysAllowed() else { return }
        MediaKey.post(command)
    }

    func seek(to seconds: Double) {
        guard var current = entry, current.hasTimeline else { return }
        let target = min(current.duration, max(0, seconds))
        current.elapsed = target
        current.fetchedAt = Date()
        entry = current
        guard !isPreview, current.source.isScriptable else { return }
        let source = current.source
        Task.detached(priority: .userInitiated) {
            PlayerScripts.seek(source, to: target)
        }
    }

    private func send(_ command: PlayerScripts.Command) {
        if isPreview {
            if command == .toggle { entry?.isPlaying.toggle() }
            return
        }
        guard let source = entry?.source, source.isScriptable else {
            sendMediaKey(command)
            return
        }
        Task.detached(priority: .userInitiated) {
            PlayerScripts.send(command, to: source)
        }
    }

    private func apply(_ next: NowPlaying?, key: String?, artwork data: Data?) {
        refreshing = false
        if let next {
            if next.differs(from: entry) { entry = next }
        } else if entry != nil {
            entry = nil
        }
        if key != artworkKey {
            artworkKey = key
            artwork = data.flatMap { NSImage(data: $0) }
        }
        if refreshAgain {
            refreshAgain = false
            refresh()
        }
    }

    nonisolated private static func artworkData(for entry: NowPlaying?) -> Data? {
        guard let entry else { return nil }
        switch entry.source.kind {
        case .music:
            return PlayerScripts.musicArtwork()
        case .spotify:
            guard let url = PlayerScripts.spotifyArtworkURL() else { return nil }
            return try? Data(contentsOf: url)
        default:
            return nil
        }
    }
}
