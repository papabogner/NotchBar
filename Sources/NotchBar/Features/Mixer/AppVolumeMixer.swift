import AppKit

/// One strip in the mixer. `playing` is false for an app that has a Core Audio process but is idle.
struct AppVolumeRow: Identifiable, Equatable {
    var id: String
    var name: String
    var level: Int
    var muted: Bool
    var playing: Bool
    /// Name of a chosen output, when this app is not using the system default.
    var outputLabel: String? = nil
}

/// The system output fader. This is the device volume, not a process tap.
struct MasterLevel: Equatable {
    var name: String
    var level: Int
    var muted: Bool
}

/// Per-app volume. Nothing is tapped, and no audio behaviour changes, until the user opens the
/// Mixer tab and moves a slider off 100% (or mutes). At 100% and unmuted the tap is removed, so
/// that app plays exactly as it does without NotchBar. A chosen output device is the exception:
/// it is remembered and applied, because the tap is what sends the app there. Other levels are
/// remembered per bundle ID, but they are not applied on the next launch until a slider moves.
@MainActor
final class AppVolumeMixer: ObservableObject {
    @Published private(set) var rows: [AppVolumeRow] = []
    /// Output devices for the strip menus. Refreshed with the row list, not on every redraw.
    @Published private(set) var outputChoices: [AudioDeviceChoice] = []
    @Published private(set) var master = MasterLevel(name: "System", level: 100, muted: false)
    /// When on, Home shows now playing and the mixer strips in one panel. Off restores the old Home.
    @Published var combineOnHome: Bool {
        didSet {
            guard !isPreview else { return }
            UserDefaults.standard.set(combineOnHome, forKey: Self.homeKey)
        }
    }
    @Published private(set) var needsExplanation = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var statusMessage: String?
    /// Saved levels are showing, but this launch hasn't applied them yet.
    @Published private(set) var showSavedHint = false
    /// Option-click solo: every other app is silenced until solo is cleared.
    @Published private(set) var soloID: String?
    /// While a call is playing, other apps are held down. Off until the menu turns it on.
    @Published private(set) var ducking = false
    @Published private(set) var duckBrowserMeet = false
    @Published private(set) var duckAppID: String?
    /// Applies the saved level, mute, and output when that app plays, without waiting for a slider.
    @Published private(set) var autoApply = false
    /// Idle apps stay off the strip until this is on. They stay greyed out.
    @Published var showSilentApps = false {
        didSet {
            guard !isPreview else { return }
            UserDefaults.standard.set(showSilentApps, forKey: "showSilentApps")
        }
    }
    /// 0 is app A, 1 is app B. Equal-power, and only a multiplier on each app's own level.
    @Published private(set) var crossfade = 0.5
    @Published private(set) var crossA: String?
    @Published private(set) var crossB: String?
    /// Extra bundles that count as the call, such as a browser tab on Meet. Set after init.
    var additionalCallBundles: @MainActor () -> Set<String> = { [] }
    private var duckGain: [String: Float] = [:]
    /// Bundle IDs that were sending sound recently, newest first. Home uses these when
    /// the live "playing" flag has not caught up yet.
    private var recentPlaying: [String] = []

    private let systemAudio: SystemAudio
    private let activity: AudioActivityMonitor
    private let isPreview: Bool
    private var saved: [String: SavedLevel] = [:]
    /// Output device UID per bundle ID. Missing means the system default, and no tap at 100%.
    private var routes: [String: String] = [:]
    private var explained: Bool
    /// Set for this launch once a slider actually asks for a tap. Not stored.
    private var engaged = false
    private var isVisible = false
    /// Home is showing the compact strips. Listing apps here still does not create taps.
    private var homeVisible = false
    private var playbackToken: UUID?
    private var outputToken: UUID?
    private var volumeToken: UUID?
    /// The crossfader is drawn before it changes any audio. Taps wait for a move or an explicit pick.
    private var crossfadeEngaged = false
    /// Coalesces tap work. A burst of slider moves becomes one pass.
    private var syncArmed = false
    /// A job is on the engine queue. Further changes wait, so taps cannot pile up behind a slow coreaudiod.
    private var syncInFlight = false
    private var syncDirty = false
    /// The next pass recreates every tap, used when the default output changes.
    private var rebuildNext = false
    private let syncDelay: TimeInterval = 0.15
    /// Type-erased so the tap engine, which needs macOS 14.4, isn't stored on this class.
    private var engineBox: Any?

    private struct SavedLevel: Codable, Equatable {
        var level: Int
        var muted: Bool
    }

    private static let levelsKey = "appVolumeLevels"
    private static let explainedKey = "appVolumeExplained"
    private static let homeKey = "homeMixerCombined"
    private static let scenesKey = "mixerScenes"
    private static let routesKey = "appOutputRoutes"
    private static let duckKey = "mixerDucking"
    private static let duckMeetKey = "mixerDuckMeet"
    private static let duckAppKey = "mixerDuckApp"
    private static let autoApplyKey = "appVolumeAutoApply"
    private static let callBundles: Set<String> = [
        "us.zoom.xos", "com.apple.FaceTime", "com.microsoft.teams", "com.microsoft.teams2", "com.cisco.webexmeetingsapp"
    ]

    private struct SceneSnapshot: Codable {
        var levels: [String: SavedLevel]
        var masterLevel: Int
        var masterMuted: Bool
    }

    init(systemAudio: SystemAudio? = nil, activity: AudioActivityMonitor? = nil, preview: [AppVolumeRow]? = nil,
         previewMaster: MasterLevel? = nil) {
        // Defaults are applied in the body. A default argument runs outside the main actor,
        // so `SystemAudio()` and `AudioActivityMonitor.shared` cannot live in the signature.
        // Locals, not the optional parameters: those names would shadow the stored properties.
        let audio = systemAudio ?? SystemAudio()
        let monitor = activity ?? AudioActivityMonitor.shared
        self.systemAudio = audio
        self.activity = monitor
        if let sample = preview {
            rows = sample
            isPreview = true
            explained = true
            combineOnHome = true
            if let previewMaster { master = previewMaster }
            return
        }
        isPreview = false
        saved = Self.loadSaved()
        routes = Self.loadRoutes()
        explained = UserDefaults.standard.bool(forKey: Self.explainedKey)
        combineOnHome = UserDefaults.standard.object(forKey: Self.homeKey) as? Bool ?? true
        ducking = UserDefaults.standard.bool(forKey: Self.duckKey)
        duckBrowserMeet = UserDefaults.standard.bool(forKey: Self.duckMeetKey)
        duckAppID = UserDefaults.standard.string(forKey: Self.duckAppKey)
        autoApply = UserDefaults.standard.bool(forKey: Self.autoApplyKey)
        showSilentApps = UserDefaults.standard.bool(forKey: "showSilentApps")
    }

    func setDucking(_ on: Bool) {
        guard !isPreview else { return }
        ducking = on
        UserDefaults.standard.set(on, forKey: Self.duckKey)
        if !on { duckGain = [:] }
        updateHooks()
        refreshDuck()
        syncTaps()
    }

    func setDuckMeet(_ on: Bool) {
        guard !isPreview else { return }
        duckBrowserMeet = on
        UserDefaults.standard.set(on, forKey: Self.duckMeetKey)
        refreshDuck()
        syncTaps()
    }

    func setDuckApp(_ bundleID: String?) {
        guard !isPreview else { return }
        duckAppID = bundleID
        if let bundleID {
            UserDefaults.standard.set(bundleID, forKey: Self.duckAppKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.duckAppKey)
        }
        refreshDuck()
        syncTaps()
    }

    /// When on, a saved level is applied as soon as that app plays.
    func setAutoApply(_ on: Bool) {
        guard !isPreview else { return }
        autoApply = on
        UserDefaults.standard.set(on, forKey: Self.autoApplyKey)
        guard on else {
            updateHooks()
            syncTaps()
            return
        }
        let wantsTap = saved.contains { $0.value.muted || $0.value.level != 100 }
        if wantsTap && !explained {
            needsExplanation = true
            return
        }
        if wantsTap { engaged = true }
        updateHooks()
        syncTaps()
    }

    /// Applies remembered levels once this object exists, when that option is on.
    func activateAutoApplyIfNeeded() {
        guard autoApply, !isPreview else { return }
        setAutoApply(true)
    }

    /// Starts listening for a call if ducking was left on. Called after init, not from it.
    func activateDuckingIfNeeded() {
        guard ducking, !isPreview else { return }
        updateHooks()
        refreshDuck()
        syncTaps()
    }

    /// Applies a remembered per-app output once this object is fully initialized.
    /// Called by the owner, not from `init`, because it installs closures that capture self.
    func applySavedRoutesIfNeeded() {
        guard !isPreview, !routes.isEmpty else { return }
        updateHooks()
        syncTaps()
    }

    /// For the debug state.
    var debugSummary: String {
        let taps: Int
        if #available(macOS 14.4, *) {
            taps = (engineBox as? MixerEngine)?.tapCount ?? 0
        } else {
            taps = 0
        }
        return "engaged=\(engaged) visible=\(isVisible) home=\(homeVisible) taps=\(taps) explained=\(explained) denied=\(permissionDenied) saved=\(saved.count)"
    }

    /// Saved levels are on the faders, but this launch has not applied them yet.
    var needsApplyHint: Bool {
        !isPreview && !engaged && rows.contains { $0.level != 100 || $0.muted }
    }

    /// Home is using the combined now-playing and mixer panel.
    var showsCombinedHome: Bool { combineOnHome && (homeVisible || isPreview) }

    func setSurfaces(mixerTab: Bool, home: Bool) {
        guard !isPreview else { return }
        isVisible = mixerTab
        homeVisible = home
        if mixerTab || home {
            refreshOutputChoices()
            publishRows()
            refreshMaster()
        }
        updateHooks()
    }

    func setShowSilent(_ on: Bool) {
        showSilentApps = on
    }

    /// Moves the crossfader. The saved level of each app stays as it was.
    /// Leaving center is what arms the taps. Sitting at the default does not.
    func setCrossfade(_ value: Double) {
        guard !isPreview else { return }
        let next = min(1, max(0, value))
        guard abs(next - crossfade) > 0.0005 else { return }
        if abs(next - 0.5) > 0.0005 { crossfadeEngaged = true }
        crossfade = next
        syncTaps()
    }

    func setCrossA(_ id: String?) {
        guard !isPreview else { return }
        if id != nil { crossfadeEngaged = true }
        crossA = id
        if let id, crossB == id { crossB = nil }
        syncTaps()
    }

    func setCrossB(_ id: String?) {
        guard !isPreview else { return }
        if id != nil { crossfadeEngaged = true }
        crossB = id
        if let id, crossA == id { crossA = nil }
        syncTaps()
    }

    /// Fills empty menus with the loudest playing apps. Does not start taps.
    private func assignDefaultCrossPairIfNeeded() {
        guard isVisible, !crossfadeEngaged else { return }
        let loud = rows.filter(\.playing).sorted { lhs, rhs in
            if lhs.level != rhs.level { return lhs.level > rhs.level }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        if crossA == nil, let id = loud.first?.id { crossA = id }
        if crossB == nil, let id = loud.first(where: { $0.id != crossA })?.id { crossB = id }
    }

    /// Equal-power multipliers. Empty until the crossfader is moved or a side is picked.
    private var crossGains: [String: Float] {
        guard crossfadeEngaged, let a = crossA, let b = crossB, a != b else { return [:] }
        let t = Float(min(1, max(0, crossfade)))
        return [a: cos(t * .pi / 2), b: sin(t * .pi / 2)]
    }

    func setMasterLevel(_ level: Int) {
        guard !isPreview else { return }
        let clamped = min(100, max(0, level))
        systemAudio.setVolume(Float(clamped) / 100)
        master.level = clamped
        if clamped > 0 { master.muted = false }
    }

    func toggleMasterMute() {
        guard !isPreview else { return }
        let next = !master.muted
        systemAudio.setMuted(next)
        master.muted = next
    }

    func setLevel(_ bundleID: String, _ level: Int) {
        guard !isPreview else { return }
        guard #available(macOS 14.4, *) else { return }
        let clamped = min(150, max(0, level))
        let muted = saved[bundleID]?.muted ?? false
        let unchanged = (saved[bundleID]?.level ?? 100) == clamped
        // After a relaunch the fader still shows the saved level, but nothing is tapped until
        // the user touches it. A drag that lands on the same number still has to apply.
        if unchanged && (engaged || (clamped == 100 && !muted)) { return }
        if !explained && (muted || clamped != 100) {
            needsExplanation = true
            return
        }
        store(bundleID, level: clamped, muted: muted)
    }

    func toggleMute(_ bundleID: String) {
        guard !isPreview else { return }
        guard #available(macOS 14.4, *) else { return }
        let muted = saved[bundleID]?.muted ?? false
        let level = saved[bundleID]?.level ?? 100
        let nextMuted = !muted
        // Unmuting back to 100% doesn't need a tap. Anything else does, and needs a yes first.
        if !explained && (nextMuted || level != 100) {
            needsExplanation = true
            return
        }
        store(bundleID, level: level, muted: nextMuted)
    }

    func toggleSolo(_ bundleID: String) {
        guard !isPreview else { return }
        guard #available(macOS 14.4, *) else { return }
        if !explained {
            needsExplanation = true
            return
        }
        soloID = soloID == bundleID ? nil : bundleID
        if soloID != nil { engaged = true }
        updateHooks()
        syncTaps()
    }

    func hasScene(_ name: String) -> Bool { loadScenes()[name] != nil }

    private func loadScenes() -> [String: SceneSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: Self.scenesKey),
              let decoded = try? JSONDecoder().decode([String: SceneSnapshot].self, from: data) else { return [:] }
        return decoded
    }

    func saveScene(_ name: String) {
        guard !isPreview else { return }
        var all = loadScenes()
        all[name] = SceneSnapshot(levels: saved, masterLevel: master.level, masterMuted: master.muted)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.scenesKey)
        }
    }

    /// Control-Option-S steps through the scenes that have been saved.
    func cycleScene() {
        let names = ["Focus", "Call"].filter { hasScene($0) }
        guard !names.isEmpty else { return }
        let name = names[sceneCursor % names.count]
        sceneCursor += 1
        recallScene(name)
    }

    private var sceneCursor = 0

    func recallScene(_ name: String) {
        guard !isPreview, let scene = loadScenes()[name] else { return }
        guard #available(macOS 14.4, *) else { return }
        let needsTap = scene.levels.contains { $0.value.muted || $0.value.level != 100 }
        if needsTap && !explained {
            needsExplanation = true
            return
        }
        saved = scene.levels.filter { $0.value.level != 100 || $0.value.muted }
        if needsTap { engaged = true }
        persist()
        let masterLevel = min(100, max(0, scene.masterLevel))
        systemAudio.setVolume(Float(masterLevel) / 100)
        if scene.masterMuted { systemAudio.setMuted(true) }
        master.level = masterLevel
        master.muted = scene.masterMuted
        publishRows()
        updateHooks()
        syncTaps()
    }

    func acceptExplanation() {
        guard !isPreview else { return }
        explained = true
        needsExplanation = false
        UserDefaults.standard.set(true, forKey: Self.explainedKey)
        if autoApply { engaged = true }
        updateHooks()
        syncTaps()
    }

    func declineExplanation() {
        needsExplanation = false
    }

    func openPrivacySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
        ]
        for text in urls {
            guard let url = URL(string: text), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }

    // MARK: Applying levels

    private func store(_ bundleID: String, level: Int, muted: Bool) {
        if level == 100 && !muted {
            saved.removeValue(forKey: bundleID)
        } else {
            saved[bundleID] = SavedLevel(level: level, muted: muted)
            engaged = true
        }
        persist()
        statusMessage = nil
        permissionDenied = false
        needsExplanation = false
        if #available(macOS 14.4, *) { (engineBox as? MixerEngine)?.unsuppress(bundleID) }
        publishRows()
        updateHooks()
        syncTaps()
    }

    /// A tap is wanted after a slider moves off 100%, the app is muted, or it has its own output device.
    private var needsActiveTaps: Bool {
        if soloID != nil { return true }
        if !routes.isEmpty { return true }
        if !duckGain.isEmpty { return true }
        if crossGains.values.contains(where: { $0 < 0.999 }) { return true }
        let savedWants = saved.contains { $0.value.muted || $0.value.level != 100 }
        if autoApply && savedWants { return true }
        return engaged && savedWants
    }

    /// Waits out a burst of changes, then applies the latest levels. Never calls Core Audio itself.
    private func syncTaps() {
        guard !isPreview else { return }
        if syncArmed { return }
        syncArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + syncDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncArmed = false
                self.performSync()
            }
        }
    }

    /// Snapshots the levels and hands them to the engine queue. The main thread does not wait.
    private func performSync() {
        publishRows()
        guard #available(macOS 14.4, *) else { return }
        if syncInFlight {
            syncDirty = true
            return
        }
        let rebuild = rebuildNext
        rebuildNext = false
        guard needsActiveTaps else {
            (engineBox as? MixerEngine)?.stopAll()
            return
        }
        syncInFlight = true
        let job = MixerEngine.Job(
            saved: saved.mapValues { MixerEngine.Level(level: $0.level, muted: $0.muted) },
            groups: activity.mixerProcessGroups(),
            permissionDenied: permissionDenied,
            solo: soloID,
            routes: routes,
            duck: duckGain,
            cross: crossGains,
            rebuild: rebuild
        )
        engine().submit(job)
    }

    /// A missing output or a failed tap, delivered on the main actor after the engine queue finishes.
    @available(macOS 14.4, *)
    fileprivate func applyEngine(_ outcome: MixerEngine.Outcome) {
        if outcome.completesSync { syncInFlight = false }
        var again = false
        if !outcome.deviceGone.isEmpty {
            for id in outcome.deviceGone { routes.removeValue(forKey: id) }
            persistRoutes()
            again = true
        }
        for problem in outcome.problems {
            let name = rows.first { $0.id == problem.id }?.name ?? "That app"
            mixerLog.error("mixer \(name, privacy: .public) \(problem.detail, privacy: .public)")
            if problem.permission {
                permissionDenied = true
                statusMessage = "\(name): \(problem.detail)"
                continue
            }
            saved.removeValue(forKey: problem.id)
            persist()
            statusMessage = "Couldn't change \(name). \(problem.detail) Left at normal volume."
            publishRows()
            updateHooks()
        }
        if outcome.completesSync && syncDirty {
            syncDirty = false
            again = true
        }
        if again { syncTaps() }
    }

    private func rebind() {
        guard #available(macOS 14.4, *) else { return }
        rebuildNext = true
        syncTaps()
    }

    private func updateHooks() {
        let watching = isVisible || homeVisible || needsActiveTaps || ducking
        if watching {
            if playbackToken == nil {
                playbackToken = activity.observePlayback { [weak self] in
                    MainActor.assumeIsolated { self?.playbackChanged() }
                }
            }
        } else if let playbackToken {
            activity.removePlaybackObserver(playbackToken)
            self.playbackToken = nil
        }
        // The master fader is on screen with the mixer tab or the combined Home panel.
        if isVisible || homeVisible {
            if volumeToken == nil {
                volumeToken = systemAudio.addVolumeHandler { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.refreshMaster() }
                }
            }
        } else if let volumeToken {
            systemAudio.removeVolumeHandler(volumeToken)
            self.volumeToken = nil
        }
        if watching {
            if outputToken == nil {
                outputToken = systemAudio.addOutputHandler { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.outputChanged() }
                }
            }
        } else if let outputToken {
            systemAudio.removeOutputHandler(outputToken)
            self.outputToken = nil
        }
    }

    private func outputChanged() {
        refreshMaster()
        refreshOutputChoices()
        rebind()
    }

    private func refreshMaster() {
        guard !isPreview else { return }
        let level = min(100, max(0, Int((systemAudio.volume * 100).rounded())))
        let next = MasterLevel(name: systemAudio.outputName, level: level, muted: systemAudio.isMuted)
        if next != master { master = next }
    }

    private func playbackChanged() {
        if ducking { refreshDuck() }
        if needsActiveTaps { syncTaps() } else { publishRows() }
    }

    /// Holds other playing apps at a quarter while a call, Meet, or the chosen app is playing.
    private func refreshDuck() {
        guard ducking, !isPreview else {
            duckGain = [:]
            return
        }
        let groups = activity.mixerProcessGroups()
        var calls = Set(groups.map(\.app.bundleID).filter { Self.callBundles.contains($0) || $0 == duckAppID })
        calls.formUnion(additionalCallBundles())
        guard !calls.isEmpty else {
            duckGain = [:]
            return
        }
        var next: [String: Float] = [:]
        for group in groups where !calls.contains(group.app.bundleID) {
            let id = group.app.bundleID
            let level = saved[id]
            let base: Float = level?.muted == true ? 0 : Float(level?.level ?? 100) / 100
            next[id] = min(base, 0.25)
        }
        duckGain = next
    }

    private func publishRows() {
        guard !isPreview else { return }
        let devices = outputChoices
        var next = activity.capableAudioApps().map { item -> AppVolumeRow in
            let level = saved[item.app.bundleID]
            let label = routes[item.app.bundleID].flatMap { uid in devices.first { $0.uid == uid }?.name }
            return AppVolumeRow(id: item.app.bundleID, name: item.app.name,
                                 level: level?.level ?? 100, muted: level?.muted ?? false, playing: item.playing,
                                 outputLabel: label)
        }
        var seen = Set(next.map(\.id))
        for (id, level) in saved where !seen.contains(id) {
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
                  running.activationPolicy == .regular else { continue }
            let label = routes[id].flatMap { uid in devices.first { $0.uid == uid }?.name }
            next.append(AppVolumeRow(id: id, name: running.localizedName ?? id,
                                      level: level.level, muted: level.muted, playing: false, outputLabel: label))
            seen.insert(id)
        }
        next.sort { lhs, rhs in
            if lhs.playing != rhs.playing { return lhs.playing && !rhs.playing }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        for id in next.filter(\.playing).map(\.id).reversed() { rememberRecent(id) }
        rows = next
        showSavedHint = isVisible && !engaged && rows.contains { $0.level != 100 || $0.muted }
        assignDefaultCrossPairIfNeeded()
    }

    /// Strips for Home: apps Core Audio says are playing, same as the green dot on the Mixer tab.
    /// When that list is empty, the Now Playing app and recently active apps fill in.
    func homeStrips(nowPlayingBundle: String?, nowPlayingName: String?, isPlaying: Bool) -> [AppVolumeRow] {
        let detected = rows.filter(\.playing)
        if !detected.isEmpty { return Array(detected.prefix(4)) }
        var fallback: [AppVolumeRow] = []
        if isPlaying, let id = nowPlayingBundle {
            fallback.append(strip(for: id, name: nowPlayingName, forcePlaying: true))
        }
        for id in recentPlaying where fallback.count < 4 && !fallback.contains(where: { $0.id == id }) {
            fallback.append(strip(for: id, name: nil, forcePlaying: true))
        }
        return fallback
    }

    private func strip(for id: String, name: String?, forcePlaying: Bool) -> AppVolumeRow {
        if var row = rows.first(where: { $0.id == id }) {
            if forcePlaying { row.playing = true }
            return row
        }
        let level = saved[id]
        let resolved = name
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName
            ?? id
        return AppVolumeRow(id: id, name: resolved, level: level?.level ?? 100,
                             muted: level?.muted ?? false, playing: forcePlaying)
    }

    private func rememberRecent(_ id: String) {
        recentPlaying.removeAll { $0 == id }
        recentPlaying.insert(id, at: 0)
        if recentPlaying.count > 6 { recentPlaying = Array(recentPlaying.prefix(6)) }
    }

    func outputDevices() -> [AudioDeviceChoice] { outputChoices }

    /// Reads the Core Audio device list once per output change, not on every redraw.
    private func refreshOutputChoices() {
        guard !isPreview else { return }
        let devices = systemAudio.outputDevices()
        if devices != outputChoices { outputChoices = devices }
    }

    /// Routes one app through a device macOS is exposing, including AirPlay. Nil returns it to the default.
    func setAppOutput(_ bundleID: String, uid: String?) {
        guard !isPreview else { return }
        guard #available(macOS 14.4, *) else { return }
        if uid != nil && !explained {
            needsExplanation = true
            return
        }
        if let uid {
            routes[bundleID] = uid
            engaged = true
        } else {
            routes.removeValue(forKey: bundleID)
        }
        persistRoutes()
        statusMessage = nil
        if #available(macOS 14.4, *) { (engineBox as? MixerEngine)?.unsuppress(bundleID) }
        publishRows()
        updateHooks()
        syncTaps()
    }

    /// Switches the system default output. This is the master strip, not a process tap.
    func setSystemOutput(uid: String) {
        guard !isPreview else { return }
        systemAudio.setDefaultOutput(uid: uid)
        refreshMaster()
    }

    private func persistRoutes() {
        guard !isPreview else { return }
        if routes.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.routesKey)
        } else {
            UserDefaults.standard.set(routes, forKey: Self.routesKey)
        }
    }

    private static func loadRoutes() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: routesKey) as? [String: String] ?? [:]
    }

    private func persist() {
        guard !isPreview else { return }
        if saved.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.levelsKey)
            return
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.levelsKey)
    }

    private static func loadSaved() -> [String: SavedLevel] {
        guard let data = UserDefaults.standard.data(forKey: levelsKey),
              let decoded = try? JSONDecoder().decode([String: SavedLevel].self, from: data) else { return [:] }
        var result: [String: SavedLevel] = [:]
        for (id, level) in decoded {
            let clamped = min(100, max(0, level.level))
            if clamped != 100 || level.muted { result[id] = SavedLevel(level: clamped, muted: level.muted) }
        }
        return result
    }

    @available(macOS 14.4, *)
    private func engine() -> MixerEngine {
        if let existing = engineBox as? MixerEngine { return existing }
        let created = MixerEngine(mixer: self)
        engineBox = created
        return created
    }
}

/// Carries a finished engine pass back to the main actor. The mixer reference is only used on the main thread.
@available(macOS 14.4, *)
private final class MixerEngineHop: @unchecked Sendable {
    private final class Ref: @unchecked Sendable {
        // Read only on the main thread, inside MainActor.assumeIsolated.
        nonisolated(unsafe) weak var mixer: AppVolumeMixer?
    }

    private let ref = Ref()

    init(_ mixer: AppVolumeMixer) {
        ref.mixer = mixer
    }

    func send(_ outcome: MixerEngine.Outcome) {
        let ref = ref
        DispatchQueue.main.async {
            MainActor.assumeIsolated { ref.mixer?.applyEngine(outcome) }
        }
    }
}

/// Owns process taps. Every Core Audio create, start, stop, and destroy runs on `queue`, never on the main thread.
@available(macOS 14.4, *)
private final class MixerEngine: @unchecked Sendable {
    struct Level: Sendable {
        var level: Int
        var muted: Bool
    }

    struct Job: Sendable {
        var saved: [String: Level]
        var groups: [PlayingProcessGroup]
        var permissionDenied: Bool
        var solo: String?
        var routes: [String: String]
        var duck: [String: Float]
        var cross: [String: Float]
        var rebuild: Bool
    }

    struct Problem: Sendable {
        var id: String
        var permission: Bool
        var detail: String
    }

    struct Outcome: Sendable {
        var deviceGone: [String] = []
        var problems: [Problem] = []
        /// This pass was a full sync, so the main actor can start the next one.
        var completesSync = false
    }

    private let queue = DispatchQueue(label: "com.local.notchbar.mixer-engine")
    private let hop: MixerEngineHop
    /// Touched only on `queue`.
    private var taps: [String: ProcessVolumeTap] = [:]
    private var suppressed: Set<String> = []
    private var healthScheduled = false
    private let countLock = NSLock()
    private var liveTaps = 0

    var tapCount: Int {
        countLock.lock()
        defer { countLock.unlock() }
        return liveTaps
    }

    init(mixer: AppVolumeMixer) {
        hop = MixerEngineHop(mixer)
    }

    func submit(_ job: Job) {
        queue.async { [weak self] in
            guard let self else { return }
            var outcome = self.apply(job)
            outcome.completesSync = true
            self.noteCount()
            self.hop.send(outcome)
        }
    }

    func stopAll() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopAllOnQueue()
            self.noteCount()
        }
    }

    func unsuppress(_ id: String) {
        let id = id
        queue.async { [weak self] in
            self?.suppressed.remove(id)
        }
    }

    deinit {
        // Hand the taps to the queue before this dictionary releases them, so stop() does not run here.
        let transferred = taps
        taps = [:]
        queue.async {
            for tap in transferred.values { tap.stop() }
        }
    }

    private func publish(_ outcome: Outcome) {
        guard !outcome.deviceGone.isEmpty || !outcome.problems.isEmpty else { return }
        hop.send(outcome)
    }

    private func apply(_ job: Job) -> Outcome {
        if job.rebuild {
            suppressed.removeAll()
            stopAllOnQueue()
        }
        var outcome = Outcome()
        var playing: [String: PlayingProcessGroup] = [:]
        for group in job.groups { playing[group.app.bundleID] = group }
        for id in Array(taps.keys) {
            let keep = playing[id].map {
                wantsTap(id: id, level: job.saved[id], solo: job.solo, route: job.routes[id], duck: job.duck[id], cross: job.cross[id])
                    && !suppressed.contains(id)
                    && taps[id]?.matches($0.processObjects, preferredUID: job.routes[id]) == true
            } ?? false
            if !keep { drop(id) }
        }
        guard !job.permissionDenied else { return outcome }
        for group in job.groups {
            let id = group.app.bundleID
            guard wantsTap(id: id, level: job.saved[id], solo: job.solo, route: job.routes[id], duck: job.duck[id], cross: job.cross[id]),
                  !suppressed.contains(id) else { continue }
            let gain = gainValue(id: id, level: job.saved[id], solo: job.solo, duck: job.duck[id], cross: job.cross[id])
            if let existing = taps[id], existing.matches(group.processObjects, preferredUID: job.routes[id]) {
                if existing.hasFault {
                    outcome.problems.append(fail(id, permission: false, detail: "The audio callback failed."))
                } else {
                    existing.setGain(gain)
                }
                continue
            }
            drop(id)
            let detail = "\(group.app.name) [\(group.processObjects.map(String.init).joined(separator: ","))]"
            mixerLog.info("starting \(detail, privacy: .public) gain=\(gain, privacy: .public)")
            switch ProcessVolumeTap.start(processObjects: group.processObjects, gain: gain, label: group.app.name, outputUID: job.routes[id]) {
            case .success(let tap):
                taps[id] = tap
                scheduleHealthCheck()
            case .failure(let error):
                if case .deviceMissing = error {
                    outcome.deviceGone.append(id)
                    continue
                }
                outcome.problems.append(fail(id, permission: error.isPermission, detail: error.summary))
                if error.isPermission { return outcome }
            }
        }
        return outcome
    }

    private func drop(_ id: String) {
        taps[id]?.stop()
        taps.removeValue(forKey: id)
    }

    private func stopAllOnQueue() {
        for tap in taps.values { tap.stop() }
        taps.removeAll()
    }

    private func noteCount() {
        let count = taps.count
        countLock.lock()
        liveTaps = count
        countLock.unlock()
    }

    /// A route, a duck, a real crossfade pull, solo, mute, or a level other than 100%.
    /// Gain 1.0 with none of those leaves the app on its own stream.
    private func wantsTap(id: String, level: Level?, solo: String?, route: String?, duck: Float?, cross: Float?) -> Bool {
        if route != nil { return true }
        if duck != nil { return true }
        if let cross, cross < 0.999 { return true }
        if let solo, solo != id { return true }
        guard let level, level.muted || level.level != 100 else { return false }
        let gain = gainValue(id: id, level: level, solo: solo, duck: duck, cross: cross)
        return abs(gain - 1) >= 0.001
    }

    private func gainValue(id: String, level: Level?, solo: String?, duck: Float?, cross: Float?) -> Float {
        let own: Float
        if let solo, solo != id {
            own = 0
        } else if let duck {
            own = min(1.5, max(0, duck))
        } else if let level {
            own = level.muted ? 0 : min(1.5, max(0, Float(level.level) / 100))
        } else if let cross, cross < 0.999 {
            own = 1
        } else {
            own = 0
        }
        guard let cross, cross < 0.999 else { return own }
        return min(1.5, max(0, own * cross))
    }

    private func fail(_ id: String, permission: Bool, detail: String) -> Problem {
        drop(id)
        suppressed.insert(id)
        return Problem(id: id, permission: permission, detail: detail)
    }

    /// A tap that never delivers a buffer, or faults, would leave the app silent. Drop it.
    private func scheduleHealthCheck() {
        guard !healthScheduled else { return }
        healthScheduled = true
        queue.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.healthScheduled = false
            let outcome = self.retireUnhealthy()
            if self.taps.contains(where: { Date().timeIntervalSince($0.value.createdAt) < 0.8 && !$0.value.healthChecked }) {
                self.scheduleHealthCheck()
            }
            self.noteCount()
            self.publish(outcome)
        }
    }

    private func retireUnhealthy() -> Outcome {
        var outcome = Outcome()
        let now = Date()
        for (id, tap) in Array(taps) {
            guard now.timeIntervalSince(tap.createdAt) >= 0.8, !tap.healthChecked else { continue }
            tap.healthChecked = true
            if tap.hasFault || !tap.didRender {
                mixerLog.error("tap unhealthy \(tap.label, privacy: .public) fault=\(tap.hasFault, privacy: .public) rendered=\(tap.didRender, privacy: .public)")
                let detail = tap.hasFault ? "The audio format didn't match." : "No audio arrived from the tap."
                outcome.problems.append(fail(id, permission: false, detail: detail))
            }
        }
        return outcome
    }
}
