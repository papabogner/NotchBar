// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import AppKit

/// Crossfader law. Applied only after the fader moves or a side is picked.
enum CrossCurve: String, CaseIterable, Identifiable, Sendable {
    case smooth, dip, cut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smooth: return String(localized: "SMOOTH")
        case .dip: return String(localized: "DIP")
        case .cut: return String(localized: "CUT")
        }
    }
}

enum DeckSide: String, CaseIterable, Identifiable, Sendable {
    case a, b
    var id: String { rawValue }
    var letter: String { self == .a ? "A" : "B" }
}

/// DJ tone controls. Coefficients are built off the render thread and published through a seqlock.
struct DeckTone: Equatable, Sendable {
    var hi = 0.5
    var mid = 0.5
    var low = 0.5
    /// 0.5 is off. Left of center is a low pass, right is a high pass.
    var filter = 0.5
    var gain = 0.5

    static let center = DeckTone()

    var isFlat: Bool {
        abs(hi - 0.5) < 0.02 && abs(mid - 0.5) < 0.02 && abs(low - 0.5) < 0.02
            && abs(filter - 0.5) < 0.02 && abs(gain - 0.5) < 0.02
    }
}

/// Linear peaks per side and RMS of the last buffer, copied off the engine queue.
struct TapMeter: Equatable, Sendable {
    var left: Float = 0
    var right: Float = 0
    var rms: Float = 0
    var peak: Float { max(left, right) }
}

/// Whether macOS lets Notch DJ create process taps (System Audio Recording).
enum CaptureStatus: String, Sendable {
    case unknown, notDetermined, authorized, denied
}

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
    var symbol: String = "speaker.wave.2.fill"
}

/// Per-app volume, decks and metering.
///
/// Nothing is tapped, and no audio behaviour changes, until something asks for it: a level other
/// than 100%, mute, solo, a route, a crossfade, a tone, or ducking during a call. At 100% and
/// unmuted the tap is removed, so that app plays exactly as it does without Notch DJ.
///
/// Remembered levels and routes are applied at launch only when System Audio Recording is
/// already allowed, so launching never shows a permission prompt. While the panel is open and
/// live meters are on, apps without a volume tap get a meter-only tap that leaves them unmuted.
@MainActor
final class AppVolumeMixer: ObservableObject {
    @Published private(set) var rows: [AppVolumeRow] = []
    /// Output devices for the strip menus. Refreshed with the row list, not on every redraw.
    @Published private(set) var outputChoices: [AudioDeviceChoice] = []
    @Published private(set) var master = MasterLevel(name: String(localized: "System"), level: 100, muted: false)
    @Published private(set) var needsExplanation = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var statusMessage: String?
    /// Saved levels are showing, but this launch hasn't applied them yet.
    @Published private(set) var showSavedHint = false
    /// CUE and S: every other app is silenced until solo is cleared.
    @Published private(set) var soloID: String?
    /// While a call is on, other playing apps are turned down to `duckLevel` of their level.
    @Published private(set) var ducking = false
    @Published private(set) var duckBrowserMeet = false
    @Published private(set) var duckAppID: String?
    @Published private(set) var duckLevel: Double = 0.25
    /// Applies the saved level, mute, and output when that app plays, without waiting for a slider.
    @Published private(set) var autoApply = true
    /// Meter-only taps for apps that have no volume tap, while the panel is open.
    @Published private(set) var liveMeters = true
    @Published private(set) var capture: CaptureStatus = .unknown
    @Published var crossCurve: CrossCurve = .smooth {
        didSet {
            guard !isPreview else { return }
            DJDefaults.suite.set(crossCurve.rawValue, forKey: "mixerCrossCurve")
            if crossfadeEngaged { syncTaps() }
        }
    }
    /// Deck EQ. Coefficients are built off the render thread and published through a seqlock.
    @Published private(set) var toneA = DeckTone() { didSet { guard !isPreview else { return }; pushTones() } }
    @Published private(set) var toneB = DeckTone() { didSet { guard !isPreview else { return }; pushTones() } }
    /// Idle apps stay off the strip until this is on. They stay greyed out.
    @Published var showSilentApps = false {
        didSet {
            guard !isPreview else { return }
            DJDefaults.suite.set(showSilentApps, forKey: "showSilentApps")
        }
    }
    /// 0 is app A, 1 is app B. Only a multiplier on each app's own level.
    @Published private(set) var crossfade = 0.5
    @Published private(set) var crossA: String?
    @Published private(set) var crossB: String?

    /// Peaks for the meters. Not published: meter views read it 30 times a second.
    let meters: MeterBank
    /// Extra bundles that count as the call. Set after init.
    var additionalCallBundles: @MainActor () -> Set<String> = { [] }
    /// A tap started (true) or was refused for permission (false). The permission store listens.
    var onCaptureResult: (@MainActor (Bool) -> Void)?

    private var duckGain: [String: Float] = [:]
    /// The Music or Spotify app that is playing, so deck A starts on it.
    private var preferredDeckApp: String?

    private let systemAudio: SystemAudio
    private let activity: AudioActivityMonitor
    private let isPreview: Bool
    private var saved: [String: SavedLevel] = [:]
    /// Output device UID per bundle ID. Missing means the system default, and no tap at 100%.
    private var routes: [String: String] = [:]
    private var explained: Bool
    /// Set for this launch once a control actually asks for a tap. Not stored.
    private var engaged = false
    private var isVisible = false
    private var playbackToken: UUID?
    private var recordingToken: UUID?
    private var outputToken: UUID?
    private var volumeToken: UUID?
    /// Meter taps outlive a close by a moment, so a quick reopen doesn't rebuild them.
    private var meterLinger: DispatchWorkItem?
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
    private static let routesKey = "appOutputRoutes"
    private static let duckKey = "mixerDucking"
    private static let duckMeetKey = "mixerDuckMeet"
    private static let duckAppKey = "mixerDuckApp"
    private static let duckLevelKey = "mixerDuckLevel"
    private static let autoApplyKey = "appVolumeAutoApply"
    private static let liveMetersKey = "liveMeters"
    /// Call and voice apps. A call is on while one of them uses the microphone.
    private static let callBundles: Set<String> = [
        "us.zoom.xos", "com.apple.FaceTime", "com.microsoft.teams", "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark", "com.hnc.Discord", "com.tinyspeck.slackmacgap",
        "com.skype.skype", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "org.whispersystems.signal-desktop",
    ]
    /// Browsers count as the call while they use the microphone, when that option is on.
    private static let browserBundles: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.apple.Safari", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "org.chromium.Chromium",
    ]

    init(systemAudio: SystemAudio? = nil, activity: AudioActivityMonitor? = nil, preview: [AppVolumeRow]? = nil,
         previewMaster: MasterLevel? = nil) {
        // Defaults are applied in the body. A default argument runs outside the main actor,
        // so `SystemAudio()` and `AudioActivityMonitor.shared` cannot live in the signature.
        // Locals, not the optional parameters: those names would shadow the stored properties.
        let audio = systemAudio ?? SystemAudio()
        let monitor = activity ?? AudioActivityMonitor.shared
        self.systemAudio = audio
        self.activity = monitor
        meters = MeterBank(simulated: preview != nil)
        if let sample = preview {
            rows = sample
            isPreview = true
            explained = true
            capture = .authorized
            if let previewMaster { master = previewMaster }
            let playing = sample.filter(\.playing)
            crossA = playing.first?.id ?? sample.first?.id
            crossB = playing.dropFirst().first?.id ?? sample.dropFirst().first?.id
            crossfade = 0.36
            toneA = DeckTone(hi: 0.58, mid: 0.5, low: 0.66, filter: 0.5, gain: 0.5)
            toneB = DeckTone(hi: 0.5, mid: 0.44, low: 0.3, filter: 0.62, gain: 0.5)
            return
        }
        isPreview = false
        saved = Self.loadSaved()
        routes = Self.loadRoutes()
        explained = DJDefaults.suite.bool(forKey: Self.explainedKey)
        ducking = DJDefaults.suite.bool(forKey: Self.duckKey)
        duckBrowserMeet = DJDefaults.suite.bool(forKey: Self.duckMeetKey)
        duckAppID = DJDefaults.suite.string(forKey: Self.duckAppKey)
        duckLevel = DJDefaults.suite.object(forKey: Self.duckLevelKey) as? Double ?? 0.25
        autoApply = DJDefaults.suite.object(forKey: Self.autoApplyKey) as? Bool ?? true
        liveMeters = DJDefaults.suite.object(forKey: Self.liveMetersKey) as? Bool ?? true
        showSilentApps = DJDefaults.suite.bool(forKey: "showSilentApps")
        crossCurve = CrossCurve(rawValue: DJDefaults.suite.string(forKey: "mixerCrossCurve") ?? "") ?? .smooth
    }

    // MARK: Permission

    /// The launch check and every later check land here. Remembered levels, routes and ducking
    /// only start once this says `authorized`, so a launch never prompts.
    func setCaptureStatus(_ status: CaptureStatus) {
        guard !isPreview, status != capture else { return }
        capture = status
        switch status {
        case .authorized:
            if !explained {
                explained = true
                DJDefaults.suite.set(true, forKey: Self.explainedKey)
            }
            needsExplanation = false
            if permissionDenied {
                permissionDenied = false
                statusMessage = nil
            }
            if #available(macOS 14.4, *) { (engineBox as? MixerEngine)?.unsuppressAll() }
            updateHooks()
            refreshDuck()
            syncTaps()
        case .denied:
            permissionDenied = true
            // Taps stop receiving audio once access is withdrawn, and a muted app would stay silent.
            if #available(macOS 14.4, *) { (engineBox as? MixerEngine)?.stopAll() }
            syncTaps()
        case .notDetermined, .unknown:
            break
        }
    }

    /// The user said yes in the banner. The tap that follows shows the system prompt.
    func acceptExplanation() {
        guard !isPreview else { return }
        explained = true
        needsExplanation = false
        DJDefaults.suite.set(true, forKey: Self.explainedKey)
        updateHooks()
        syncTaps()
    }

    func declineExplanation() {
        needsExplanation = false
    }

    func dismissStatus() {
        statusMessage = nil
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

    // MARK: Settings

    func setDucking(_ on: Bool) {
        guard !isPreview else { return }
        ducking = on
        DJDefaults.suite.set(on, forKey: Self.duckKey)
        if !on { duckGain = [:] }
        updateHooks()
        refreshDuck()
        syncTaps()
    }

    func setDuckMeet(_ on: Bool) {
        guard !isPreview else { return }
        duckBrowserMeet = on
        DJDefaults.suite.set(on, forKey: Self.duckMeetKey)
        refreshDuck()
        syncTaps()
    }

    func setDuckApp(_ bundleID: String?) {
        guard !isPreview else { return }
        duckAppID = bundleID
        if let bundleID {
            DJDefaults.suite.set(bundleID, forKey: Self.duckAppKey)
        } else {
            DJDefaults.suite.removeObject(forKey: Self.duckAppKey)
        }
        refreshDuck()
        syncTaps()
    }

    func setDuckLevel(_ level: Double) {
        guard !isPreview else { return }
        duckLevel = min(0.8, max(0, level))
        DJDefaults.suite.set(duckLevel, forKey: Self.duckLevelKey)
        refreshDuck()
        syncTaps()
    }

    /// When on, a saved level is applied as soon as that app plays.
    func setAutoApply(_ on: Bool) {
        guard !isPreview else { return }
        autoApply = on
        DJDefaults.suite.set(on, forKey: Self.autoApplyKey)
        updateHooks()
        syncTaps()
    }

    func setLiveMeters(_ on: Bool) {
        guard !isPreview else { return }
        liveMeters = on
        DJDefaults.suite.set(on, forKey: Self.liveMetersKey)
        if !on { meters.clear() }
        syncTaps()
    }

    func setShowSilent(_ on: Bool) {
        showSilentApps = on
    }

    /// Saved levels are on the faders, but this launch has not applied them yet.
    var needsApplyHint: Bool {
        !isPreview && !engaged && !(autoApply && capture == .authorized) && rows.contains { $0.level != 100 || $0.muted }
    }

    var canRemember: Bool { capture == .authorized }

    // MARK: Visibility

    /// The panel opened or closed. Listing apps never creates taps by itself; meters do, when allowed.
    func setPanelVisible(_ visible: Bool) {
        guard !isPreview, visible != isVisible else { return }
        isVisible = visible
        meterLinger?.cancel()
        meterLinger = nil
        if visible {
            activity.start()
            refreshOutputChoices()
            publishRows()
            refreshMaster()
        }
        updateHooks()
        refreshMetering()
        if visible {
            if wantsMeters { syncTaps() }
        } else if liveMeters && capture == .authorized {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isVisible else { return }
                    self.meterLinger = nil
                    self.syncTaps()
                }
            }
            meterLinger = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        }
    }

    /// Deck A starts on this app when nothing is picked yet. Not published.
    func setPreferredDeckApp(_ bundleID: String?) {
        preferredDeckApp = bundleID
    }

    // MARK: Decks

    func deckID(_ side: DeckSide) -> String? { side == .a ? crossA : crossB }

    func tone(_ side: DeckSide) -> DeckTone { side == .a ? toneA : toneB }

    func row(_ id: String?) -> AppVolumeRow? {
        guard let id else { return nil }
        return rows.first { $0.id == id }
    }

    func deckRow(_ side: DeckSide) -> AppVolumeRow? { row(deckID(side)) }

    func setTone(_ side: DeckSide, _ tone: DeckTone) {
        if !isPreview && !explained && !tone.isFlat {
            needsExplanation = true
            return
        }
        if side == .a { toneA = tone } else { toneB = tone }
    }

    func assign(_ side: DeckSide, _ id: String?) {
        if side == .a { setCrossA(id) } else { setCrossB(id) }
    }

    func setDeckLevel(_ side: DeckSide, _ level: Int) {
        guard let id = deckID(side) else { return }
        setLevel(id, level)
    }

    func toggleCue(_ side: DeckSide) {
        guard let id = deckID(side) else { return }
        toggleSolo(id)
    }

    /// Moves the crossfader. The saved level of each app stays as it was.
    /// Leaving center is what arms the taps. Sitting at the default does not.
    func setCrossfade(_ value: Double) {
        let next = min(1, max(0, value))
        guard abs(next - crossfade) > 0.0005 else { return }
        if isPreview {
            crossfade = next
            return
        }
        if abs(next - 0.5) > 0.0005 { crossfadeEngaged = true }
        crossfade = next
        syncTaps()
    }

    func setCrossA(_ id: String?) {
        if isPreview {
            crossA = id
            if let id, crossB == id { crossB = nil }
            return
        }
        if id != nil { crossfadeEngaged = true }
        crossA = id
        if let id, crossB == id { crossB = nil }
        syncTaps()
    }

    func setCrossB(_ id: String?) {
        if isPreview {
            crossB = id
            if let id, crossA == id { crossA = nil }
            return
        }
        if id != nil { crossfadeEngaged = true }
        crossB = id
        if let id, crossA == id { crossA = nil }
        syncTaps()
    }

    /// Fills empty decks with the playing apps, Music or Spotify first. Does not start taps.
    private func assignDefaultCrossPairIfNeeded() {
        guard isVisible, !crossfadeEngaged else { return }
        let preferred = preferredDeckApp
        let loud = rows.filter(\.playing).sorted { lhs, rhs in
            if (lhs.id == preferred) != (rhs.id == preferred) { return lhs.id == preferred }
            if lhs.level != rhs.level { return lhs.level > rhs.level }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        if crossA == nil, let id = loud.first?.id { crossA = id }
        if crossB == nil, let id = loud.first(where: { $0.id != crossA })?.id { crossB = id }
    }

    /// Curve multipliers. Empty until the crossfader is moved or a side is picked.
    private var crossGains: [String: Float] {
        guard crossfadeEngaged, let a = crossA, let b = crossB, a != b else { return [:] }
        let t = Float(min(1, max(0, crossfade)))
        switch crossCurve {
        case .smooth:
            return [a: cos(t * .pi / 2), b: sin(t * .pi / 2)]
        case .dip:
            return [a: 1 - t, b: t]
        case .cut:
            if t < 0.48 { return [a: 1, b: 0] }
            if t > 0.52 { return [a: 0, b: 1] }
            let blend = (t - 0.48) / 0.04
            return [a: 1 - blend, b: blend]
        }
    }

    // MARK: Meters

    /// Copies tap peaks while the panel is open. Does nothing until a tap engine exists.
    private func refreshMetering() {
        guard !isPreview else { return }
        guard #available(macOS 14.4, *) else { return }
        (engineBox as? MixerEngine)?.setMetering(isVisible)
    }

    fileprivate func applyMeters(_ levels: [String: TapMeter]) {
        guard isVisible else { return }
        meters.ingest(levels, now: MeterBank.now)
    }

    private var wantsMeters: Bool {
        !isPreview && isVisible && liveMeters && capture == .authorized && !permissionDenied
    }

    private func toneMap() -> [String: DeckTone] {
        var map: [String: DeckTone] = [:]
        if let id = crossA { map[id] = toneA }
        if let id = crossB { map[id] = toneB }
        return map
    }

    private func pushTones() {
        guard !isPreview else { return }
        if #available(macOS 14.4, *) {
            (engineBox as? MixerEngine)?.pushTones(toneMap())
        }
        syncTaps()
    }

    // MARK: Levels

    func setMasterLevel(_ level: Int) {
        let clamped = min(100, max(0, level))
        if isPreview {
            master.level = clamped
            return
        }
        systemAudio.setVolume(Float(clamped) / 100)
        master.level = clamped
        if clamped > 0 { master.muted = false }
    }

    func toggleMasterMute() {
        let next = !master.muted
        if !isPreview { systemAudio.setMuted(next) }
        master.muted = next
    }

    func setLevel(_ bundleID: String, _ level: Int) {
        let clamped = min(150, max(0, level))
        if isPreview {
            if let index = rows.firstIndex(where: { $0.id == bundleID }) { rows[index].level = clamped }
            return
        }
        guard #available(macOS 14.4, *) else { return }
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
        if isPreview {
            if let index = rows.firstIndex(where: { $0.id == bundleID }) { rows[index].muted.toggle() }
            return
        }
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
        if isPreview {
            soloID = soloID == bundleID ? nil : bundleID
            return
        }
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

    /// Puts every app back to 100%, unmuted, on the default output.
    func resetAll() {
        guard !isPreview else { return }
        saved = [:]
        routes = [:]
        soloID = nil
        persist()
        persistRoutes()
        statusMessage = nil
        publishRows()
        updateHooks()
        syncTaps()
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
        if capture != .denied { permissionDenied = false }
        needsExplanation = false
        if #available(macOS 14.4, *) { (engineBox as? MixerEngine)?.unsuppress(bundleID) }
        publishRows()
        updateHooks()
        syncTaps()
    }

    private var savedWantsTap: Bool {
        saved.contains { $0.value.muted || $0.value.level != 100 }
    }

    /// A tap is wanted after a slider moves off 100%, the app is muted, or it has its own output device.
    /// Remembered state (levels, routes, ducking) only counts once capture is allowed.
    private var needsActiveTaps: Bool {
        let allowed = capture == .authorized
        if soloID != nil { return true }
        if !routes.isEmpty && (allowed || engaged) { return true }
        if !duckGain.isEmpty && allowed { return true }
        if crossGains.values.contains(where: { $0 < 0.999 }) { return true }
        if crossA != nil && !toneA.isFlat { return true }
        if let b = crossB, b != crossA, !toneB.isFlat { return true }
        if autoApply && allowed && savedWantsTap { return true }
        return engaged && savedWantsTap
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
        let meterTaps = wantsMeters
        guard needsActiveTaps || meterTaps else {
            (engineBox as? MixerEngine)?.stopAll()
            refreshMetering()
            return
        }
        syncInFlight = true
        let job = MixerEngine.Job(
            saved: saved.mapValues { MixerEngine.Level(level: $0.level, muted: $0.muted) },
            groups: activity.mixerProcessGroups(),
            permissionDenied: permissionDenied || capture == .denied,
            solo: soloID,
            routes: routes,
            duck: duckGain,
            cross: crossGains,
            rebuild: rebuild,
            tones: toneMap(),
            meters: meterTaps
        )
        engine().submit(job)
        refreshMetering()
    }

    /// A missing output or a failed tap, delivered on the main actor after the engine queue finishes.
    @available(macOS 14.4, *)
    fileprivate func applyEngine(_ outcome: MixerEngine.Outcome) {
        if outcome.completesSync { syncInFlight = false }
        if outcome.started && capture != .authorized { onCaptureResult?(true) }
        if outcome.meterPermissionDenied { onCaptureResult?(false) }
        var again = false
        if !outcome.deviceGone.isEmpty {
            for id in outcome.deviceGone { routes.removeValue(forKey: id) }
            persistRoutes()
            again = true
        }
        for problem in outcome.problems {
            let name = rows.first { $0.id == problem.id }?.name ?? String(localized: "That app")
            mixerLog.error("mixer \(name, privacy: .public) \(problem.detail, privacy: .public)")
            if problem.permission {
                permissionDenied = true
                statusMessage = problem.detail
                onCaptureResult?(false)
                continue
            }
            saved.removeValue(forKey: problem.id)
            persist()
            let detail = problem.detail
            statusMessage = String(localized: "Couldn't change \(name). \(detail) It's back at normal volume.")
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
        let watching = isVisible || needsActiveTaps || ducking
        if watching {
            activity.start()
            if playbackToken == nil {
                playbackToken = activity.observePlayback { [weak self] in
                    MainActor.assumeIsolated { self?.playbackChanged() }
                }
            }
        } else if let playbackToken {
            activity.removePlaybackObserver(playbackToken)
            self.playbackToken = nil
        }
        if ducking {
            if recordingToken == nil {
                recordingToken = activity.observeRecording { [weak self] in
                    MainActor.assumeIsolated { self?.recordingChanged() }
                }
            }
        } else if let recordingToken {
            activity.removeRecordingObserver(recordingToken)
            self.recordingToken = nil
        }
        // The master control is on screen only with the panel.
        if isVisible {
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
        let next = MasterLevel(name: systemAudio.outputName, level: level, muted: systemAudio.isMuted,
                               symbol: systemAudio.outputSymbol)
        if next != master { master = next }
    }

    private func playbackChanged() {
        if ducking { refreshDuck() }
        if needsActiveTaps || wantsMeters { syncTaps() } else { publishRows() }
    }

    private func recordingChanged() {
        guard ducking else { return }
        let before = duckGain
        refreshDuck()
        if duckGain != before { syncTaps() }
    }

    /// While a call app uses the microphone, every other playing app goes down to `duckLevel`
    /// of its own level. The chosen app also counts while it plays.
    private func refreshDuck() {
        guard ducking, !isPreview, capture == .authorized else {
            duckGain = [:]
            return
        }
        let groups = activity.mixerProcessGroups()
        var calls = Set(activity.recording.map(\.bundleID).filter { id in
            Self.callBundles.contains(id) || id == duckAppID || (duckBrowserMeet && Self.browserBundles.contains(id))
        })
        // FaceTime's audio also shows up as an ordinary player.
        for group in groups where group.app.bundleID == "com.apple.FaceTime" || group.app.bundleID == duckAppID {
            calls.insert(group.app.bundleID)
        }
        calls.formUnion(additionalCallBundles())
        guard !calls.isEmpty else {
            duckGain = [:]
            return
        }
        let depth = Float(duckLevel)
        var next: [String: Float] = [:]
        for group in groups where !calls.contains(group.app.bundleID) {
            let id = group.app.bundleID
            let level = saved[id]
            let base: Float = level?.muted == true ? 0 : Float(level?.level ?? 100) / 100
            next[id] = base * depth
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
        if next != rows { rows = next }
        let hint = isVisible && needsApplyHint
        if hint != showSavedHint { showSavedHint = hint }
        assignDefaultCrossPairIfNeeded()
    }

    // MARK: Outputs

    func outputDevices() -> [AudioDeviceChoice] { outputChoices }

    /// The system default output, for the settings menu.
    func currentOutputUID() -> String { isPreview ? "" : systemAudio.currentOutputUID() }

    /// Fills the device menu. Settings can open before the panel does.
    func refreshDevices() {
        refreshOutputChoices()
        refreshMaster()
    }

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

    /// The device an app is routed to, or nil for the system default.
    func route(for bundleID: String) -> String? { routes[bundleID] }

    /// Switches the system default output. This is the master strip, not a process tap.
    func setSystemOutput(uid: String) {
        guard !isPreview else { return }
        systemAudio.setDefaultOutput(uid: uid)
        refreshMaster()
    }

    private func persistRoutes() {
        guard !isPreview else { return }
        if routes.isEmpty {
            DJDefaults.suite.removeObject(forKey: Self.routesKey)
        } else {
            DJDefaults.suite.set(routes, forKey: Self.routesKey)
        }
    }

    private static func loadRoutes() -> [String: String] {
        DJDefaults.suite.dictionary(forKey: routesKey) as? [String: String] ?? [:]
    }

    private func persist() {
        guard !isPreview else { return }
        if saved.isEmpty {
            DJDefaults.suite.removeObject(forKey: Self.levelsKey)
            return
        }
        DJDefaults.suite.set(try? JSONEncoder().encode(saved), forKey: Self.levelsKey)
    }

    private static func loadSaved() -> [String: SavedLevel] {
        guard let data = DJDefaults.suite.data(forKey: levelsKey),
              let decoded = try? JSONDecoder().decode([String: SavedLevel].self, from: data) else { return [:] }
        var result: [String: SavedLevel] = [:]
        for (id, level) in decoded {
            let clamped = min(150, max(0, level.level))
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

    func sendMeters(_ levels: [String: TapMeter]) {
        let ref = ref
        DispatchQueue.main.async {
            MainActor.assumeIsolated { ref.mixer?.applyMeters(levels) }
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
        var tones: [String: DeckTone]
        /// Meter-only taps for playing apps that have no volume tap.
        var meters: Bool
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
        /// A tap started, so System Audio Recording is allowed.
        var started = false
        /// A meter tap was refused for permission. Meters stay off until the next rebuild.
        var meterPermissionDenied = false
    }

    private let queue = DispatchQueue(label: "com.local.notchdj.mixer-engine")
    private let hop: MixerEngineHop
    /// Touched only on `queue`.
    private var taps: [String: ProcessVolumeTap] = [:]
    private var suppressed: Set<String> = []
    /// Apps whose meter tap failed. They show no meter, and nothing is reported.
    private var meterSuppressed: Set<String> = []
    private var metersBlocked = false
    private var healthScheduled = false
    private var metering = false
    private var meterScheduled = false
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

    func unsuppressAll() {
        queue.async { [weak self] in
            guard let self else { return }
            self.suppressed.removeAll()
            self.meterSuppressed.removeAll()
            self.metersBlocked = false
        }
    }

    /// Reads atomic peaks from existing taps. No Core Audio calls. Stops when the panel closes.
    func setMetering(_ on: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.metering = on
            if on { self.scheduleMeter() }
        }
    }

    private func scheduleMeter() {
        guard metering, !meterScheduled else { return }
        meterScheduled = true
        queue.asyncAfter(deadline: .now() + 1.0 / 30) { [weak self] in
            guard let self else { return }
            self.meterScheduled = false
            guard self.metering else { return }
            var levels: [String: TapMeter] = [:]
            for (id, tap) in self.taps {
                let snap = tap.meterSnapshot()
                levels[id] = TapMeter(left: snap.left, right: snap.right, rms: sqrt(max(0, snap.meanSquare)))
            }
            self.hop.sendMeters(levels)
            self.scheduleMeter()
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
            meterSuppressed.removeAll()
            metersBlocked = false
            stopAllOnQueue()
        }
        defer { applyTones(job) }
        var outcome = Outcome()
        var playing: [String: PlayingProcessGroup] = [:]
        for group in job.groups { playing[group.app.bundleID] = group }
        for id in Array(taps.keys) {
            guard let tap = taps[id] else { continue }
            var keep = false
            if let group = playing[id] {
                let volume = wantsVolume(id, job)
                if tap.meterOnly {
                    keep = !volume && job.meters && !job.permissionDenied && !metersBlocked
                        && !meterSuppressed.contains(id) && tap.matches(group.processObjects, preferredUID: nil)
                } else {
                    keep = volume && tap.matches(group.processObjects, preferredUID: job.routes[id])
                }
            }
            if !keep { drop(id) }
        }
        guard !job.permissionDenied else { return outcome }
        for group in job.groups {
            let id = group.app.bundleID
            if wantsVolume(id, job) {
                let gain = gainValue(id: id, level: job.saved[id], solo: job.solo, duck: job.duck[id], cross: job.cross[id])
                if let existing = taps[id], !existing.meterOnly,
                   existing.matches(group.processObjects, preferredUID: job.routes[id]) {
                    if existing.hasFault {
                        outcome.problems.append(fail(id, permission: false, detail: String(localized: "The audio callback failed.")))
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
                    outcome.started = true
                    scheduleHealthCheck()
                case .failure(let error):
                    if case .deviceMissing = error {
                        outcome.deviceGone.append(id)
                        continue
                    }
                    outcome.problems.append(fail(id, permission: error.isPermission, detail: error.summary))
                    if error.isPermission { return outcome }
                }
                continue
            }
            guard job.meters, !metersBlocked, !meterSuppressed.contains(id), taps[id] == nil else { continue }
            switch ProcessVolumeTap.start(processObjects: group.processObjects, gain: 1, label: group.app.name, meterOnly: true) {
            case .success(let tap):
                taps[id] = tap
                outcome.started = true
                scheduleHealthCheck()
            case .failure(let error):
                meterSuppressed.insert(id)
                if error.isPermission {
                    metersBlocked = true
                    outcome.meterPermissionDenied = true
                    return outcome
                }
            }
        }
        return outcome
    }

    private func wantsVolume(_ id: String, _ job: Job) -> Bool {
        guard !suppressed.contains(id) else { return false }
        return wantsTap(id: id, level: job.saved[id], solo: job.solo, route: job.routes[id], duck: job.duck[id],
                        cross: job.cross[id], filters: job.tones[id]?.isFlat == false)
    }

    private func applyTones(_ job: Job) {
        for (id, tap) in taps where !tap.meterOnly {
            tap.setDeckTone(job.tones[id] ?? .center)
        }
    }

    func pushTones(_ tones: [String: DeckTone]) {
        let tones = tones
        queue.async { [weak self] in
            guard let self else { return }
            for (id, tap) in self.taps where !tap.meterOnly {
                tap.setDeckTone(tones[id] ?? .center)
            }
        }
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
    private func wantsTap(id: String, level: Level?, solo: String?, route: String?, duck: Float?, cross: Float?, filters: Bool) -> Bool {
        if filters { return true }
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
        } else {
            // No saved level means the app is still at its own 100%, including a tone-only tap.
            own = 1
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
            guard tap.hasFault || !tap.didRender else { continue }
            mixerLog.error("tap unhealthy \(tap.label, privacy: .public) meterOnly=\(tap.meterOnly, privacy: .public) fault=\(tap.hasFault, privacy: .public) rendered=\(tap.didRender, privacy: .public)")
            if tap.meterOnly {
                drop(id)
                meterSuppressed.insert(id)
                continue
            }
            let detail = tap.hasFault
                ? String(localized: "The audio format didn't match.")
                : String(localized: "No audio arrived from the tap.")
            outcome.problems.append(fail(id, permission: false, detail: detail))
        }
        return outcome
    }
}
