import AppKit

/// Sample apps and a track for template previews. Nothing here touches audio.
enum PreviewData {
    static let rows: [AppVolumeRow] = [
        AppVolumeRow(id: "com.spotify.client", name: "Spotify", level: 100, muted: false, playing: true),
        AppVolumeRow(id: "com.apple.Safari", name: "Safari", level: 82, muted: false, playing: true),
        AppVolumeRow(id: "com.apple.Music", name: "Music", level: 100, muted: false, playing: false),
        AppVolumeRow(id: "us.zoom.xos", name: "zoom.us", level: 100, muted: false, playing: false),
    ]

    static let master = MasterLevel(name: "MacBook Pro Speakers", level: 64, muted: false, symbol: "laptopcomputer")

    static let track = NowPlaying(source: .spotify, trackID: "preview", title: "Midnight City", artist: "M83",
                                  album: "Hurry Up, We're Dreaming", duration: 243, elapsed: 61, isPlaying: true)
}

/// A complete set of preview objects, so a template can draw with made-up audio and meters.
@MainActor
final class PreviewStage: ObservableObject {
    let mixer: AppVolumeMixer
    let now: NowPlayingMonitor
    let prefs: DJPreferences
    let permissions: PermissionCenter
    let model: DJModel

    init(systemAudio: SystemAudio? = nil) {
        mixer = AppVolumeMixer(systemAudio: systemAudio, preview: PreviewData.rows, previewMaster: PreviewData.master)
        now = NowPlayingMonitor(preview: PreviewData.track)
        prefs = DJPreferences(preview: .studio)
        permissions = PermissionCenter(preview: .authorized)
        model = DJModel(mixer: mixer, now: now, prefs: prefs, permissions: permissions)
    }
}
