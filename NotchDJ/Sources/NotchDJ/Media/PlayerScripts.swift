// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import AppKit

/// AppleScript access to Music and Spotify.
///
/// Every call here blocks on an Apple Event, so call these off the main thread. Only call them
/// for apps that are already running: sending an event to a closed app launches it.
enum PlayerScripts {
    enum Command: Sendable { case toggle, next, previous }

    private static let separator = "\u{1F}"

    static func nowPlaying(_ source: MediaSource) -> NowPlaying? {
        guard let script = stateScript(for: source),
              let output = run(script)?.stringValue, !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: separator)
        guard parts.count == 7 else { return nil }
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return NowPlaying(source: source, trackID: parts[0], title: parts[1], artist: parts[2], album: parts[3],
                          duration: number(parts[4]), elapsed: number(parts[5]), isPlaying: parts[6] == "playing")
    }

    static func send(_ command: Command, to source: MediaSource) {
        guard source.isScriptable else { return }
        let verb: String
        switch (source.kind, command) {
        case (_, .toggle): verb = "playpause"
        case (_, .next): verb = "next track"
        case (.music, .previous): verb = "back track"
        case (_, .previous): verb = "previous track"
        }
        run("tell application id \"\(source.bundleID)\" to \(verb)")
    }

    static func seek(_ source: MediaSource, to seconds: Double) {
        guard source.isScriptable else { return }
        run("tell application id \"\(source.bundleID)\" to set player position to \(String(format: "%.2f", seconds))")
    }

    static func musicArtwork() -> Data? {
        let script = """
        tell application id "com.apple.Music"
            try
                return raw data of artwork 1 of current track
            on error
                return data of artwork 1 of current track
            end try
        end tell
        """
        guard let data = run(script)?.data, !data.isEmpty else { return nil }
        return data
    }

    static func spotifyArtworkURL() -> URL? {
        run("tell application id \"com.spotify.client\" to return artwork url of current track")?.stringValue.flatMap(URL.init(string:))
    }

    /// Runs AppleScript with a short timeout. Returns nil on any error, including a denied
    /// Automation permission.
    @discardableResult
    static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: "with timeout of 3 seconds\n\(source)\nend timeout")?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    private static func stateScript(for source: MediaSource) -> String? {
        let s = separator
        switch source.kind {
        case .music:
            return """
            tell application id "com.apple.Music"
                if player state is stopped then return ""
                set t to current track
                return (persistent ID of t) & "\(s)" & (name of t) & "\(s)" & (artist of t) & "\(s)" & (album of t) & "\(s)" & ((duration of t) as string) & "\(s)" & ((player position) as string) & "\(s)" & ((player state) as string)
            end tell
            """
        case .spotify:
            return """
            tell application id "com.spotify.client"
                if player state is stopped then return ""
                set t to current track
                return (id of t) & "\(s)" & (name of t) & "\(s)" & (artist of t) & "\(s)" & (album of t) & "\(s)" & (((duration of t) / 1000) as string) & "\(s)" & ((player position) as string) & "\(s)" & ((player state) as string)
            end tell
            """
        default:
            return nil
        }
    }
}
