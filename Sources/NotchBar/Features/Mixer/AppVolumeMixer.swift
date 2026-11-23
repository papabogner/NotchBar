import AppKit

/// One row in the mixer: a playing app and the level the user asked for.
struct AppVolumeRow: Identifiable, Equatable {
    var id: String
    var name: String
    var level: Int
    var muted: Bool
}

/// Per-app volume. Nothing is tapped, and no audio behaviour changes, until the user opens the
/// Mixer tab and moves a slider off 100% (or mutes). At 100% and unmuted the tap is removed, so
/// that app plays exactly as it does without NotchBar. Levels are remembered per bundle ID, but
/// they are not applied on the next launch until the user moves a slider again.
@MainActor
final class AppVolumeMixer: ObservableObject {
    @Published private(set) var rows: [AppVolumeRow] = []
    @Published private(set) var needsExplanation = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var statusMessage: String?
    /// Saved levels are showing, but this launch hasn't applied them yet.
    @Published private(set) var showSavedHint = false

    private let systemAudio: SystemAudio
    private let activity: AudioActivityMonitor
    private let isPreview: Bool
    private var saved: [String: SavedLevel] = [:]
    private var explained: Bool
    /// Set for this launch once a slider actually asks for a tap. Not stored.
    private var engaged = false
    private var isVisible = false
    private var playbackToken: UUID?
    private var outputToken: UUID?
    private var syncing = false
    /// Type-erased so the tap engine, which needs macOS 14.4, isn't stored on this class.
    private var engineBox: Any?

    private struct SavedLevel: Codable, Equatable {
        var level: Int
        var muted: Bool
    }

    private static let levelsKey = "appVolumeLevels"
    private static let explainedKey = "appVolumeExplained"

    init(systemAudio: SystemAudio? = nil, activity: AudioActivityMonitor? = nil, preview: [AppVolumeRow]? = nil) {
        // Defaults are applied in the body. A default argument runs outside the main actor,
        // so `SystemAudio()` and `AudioActivityMonitor.shared` cannot live in the signature.
        self.systemAudio = systemAudio ?? SystemAudio()
        self.activity = activity ?? AudioActivityMonitor.shared
        if let preview {
            rows = preview
            isPreview = true
            explained = true
            return
        }
        isPreview = false
        saved = Self.loadSaved()
        explained = UserDefaults.standard.bool(forKey: Self.explainedKey)
    }

    /// For the debug state.
    var debugSummary: String {
        let taps: Int
        if #available(macOS 14.4, *) {
            taps = (engineBox as? Engine)?.tapCount ?? 0
        } else {
            taps = 0
        }
        return "engaged=\(engaged) visible=\(isVisible) taps=\(taps) explained=\(explained) denied=\(permissionDenied) saved=\(saved.count)"
    }

    func setVisible(_ visible: Bool) {
        guard !isPreview else { return }
        isVisible = visible
        if visible { publishRows() }
        updateHooks()
    }

    func setLevel(_ bundleID: String, _ level: Int) {
        guard !isPreview else { return }
        guard #available(macOS 14.4, *) else { return }
        let clamped = min(100, max(0, level))
        let muted = saved[bundleID]?.muted ?? false
        if (saved[bundleID]?.level ?? 100) == clamped { return }
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

    func acceptExplanation() {
        guard !isPreview else { return }
        explained = true
        needsExplanation = false
        UserDefaults.standard.set(true, forKey: Self.explainedKey)
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
        if #available(macOS 14.4, *) { (engineBox as? Engine)?.unsuppress(bundleID) }
        publishRows()
        updateHooks()
        syncTaps()
    }

    /// A tap is wanted only after the user has moved a slider this launch, and only off 100% or muted.
    private var needsActiveTaps: Bool {
        engaged && saved.contains { $0.value.muted || $0.value.level != 100 }
    }

    private func syncTaps() {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let groups = activity.playingProcessGroups()
        if #available(macOS 14.4, *), needsActiveTaps {
            engine().sync(saved: saved, groups: groups, permissionDenied: permissionDenied)
        } else if #available(macOS 14.4, *) {
            (engineBox as? Engine)?.stopAll()
        }
        publishRows(groups)
    }

    private func rebind() {
        guard needsActiveTaps, !permissionDenied else { return }
        guard #available(macOS 14.4, *) else { return }
        let engine = engine()
        engine.clearSuppression()
        engine.stopAll()
        syncTaps()
    }

    private func updateHooks() {
        if isVisible || needsActiveTaps {
            if playbackToken == nil {
                playbackToken = activity.observePlayback { [weak self] in
                    MainActor.assumeIsolated { self?.playbackChanged() }
                }
            }
        } else if let playbackToken {
            activity.removePlaybackObserver(playbackToken)
            self.playbackToken = nil
        }
        if needsActiveTaps {
            if outputToken == nil {
                outputToken = systemAudio.addOutputHandler { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.rebind() }
                }
            }
        } else if let outputToken {
            systemAudio.removeOutputHandler(outputToken)
            self.outputToken = nil
        }
    }

    private func playbackChanged() {
        if needsActiveTaps { syncTaps() } else { publishRows() }
    }

    private func publishRows() {
        publishRows(activity.playingProcessGroups())
    }

    private func publishRows(_ groups: [PlayingProcessGroup]) {
        guard !isPreview else { return }
        rows = groups.map { group in
            let level = saved[group.app.bundleID]
            return AppVolumeRow(id: group.app.bundleID, name: group.app.name,
                                 level: level?.level ?? 100, muted: level?.muted ?? false)
        }
        showSavedHint = isVisible && !engaged && rows.contains { $0.level != 100 || $0.muted }
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
    private func engine() -> Engine {
        if let existing = engineBox as? Engine { return existing }
        let created = Engine { [weak self] bundleID, permission in
            MainActor.assumeIsolated {
                guard let self else { return }
                if permission {
                    self.permissionDenied = true
                    self.statusMessage = "Audio access is off, so the volume was left unchanged."
                    return
                }
                // The slider was ahead of the audio. Put it back so it doesn't claim a level we aren't applying.
                let name = self.rows.first { $0.id == bundleID }?.name ?? "That app"
                self.saved.removeValue(forKey: bundleID)
                self.persist()
                self.statusMessage = "Couldn't change \(name)'s volume, so it was left as it is."
                self.publishRows()
                self.updateHooks()
            }
        }
        engineBox = created
        return created
    }

    /// Taps for the apps the user has turned down. Created only on macOS 14.4+.
    @available(macOS 14.4, *)
    @MainActor
    private final class Engine {
        var onProblem: (String, Bool) -> Void
        private var taps: [String: ProcessVolumeTap] = [:]
        private var suppressed: Set<String> = []
        private var healthScheduled = false
        var tapCount: Int { taps.count }

        init(onProblem: @escaping (String, Bool) -> Void) {
            self.onProblem = onProblem
        }

        func sync(saved: [String: SavedLevel], groups: [PlayingProcessGroup], permissionDenied: Bool) {
            var playing: [String: PlayingProcessGroup] = [:]
            for group in groups { playing[group.app.bundleID] = group }
            for id in Array(taps.keys) {
                let keep = playing[id].map { wantsTap(saved[id]) && !suppressed.contains(id) && taps[id]?.matches($0.processObjects) == true } ?? false
                if !keep {
                    taps[id]?.stop()
                    taps.removeValue(forKey: id)
                }
            }
            guard !permissionDenied else { return }
            for group in groups {
                let id = group.app.bundleID
                guard wantsTap(saved[id]), !suppressed.contains(id) else { continue }
                let gain = gainValue(saved[id])
                if let existing = taps[id], existing.matches(group.processObjects) {
                    if existing.hasFault {
                        fail(id, permission: false)
                    } else {
                        existing.setGain(gain)
                    }
                    continue
                }
                taps[id]?.stop()
                taps[id] = nil
                switch ProcessVolumeTap.start(processObjects: group.processObjects, gain: gain) {
                case .success(let tap):
                    taps[id] = tap
                    scheduleHealthCheck()
                case .failure(let error):
                    let permission = error == .permissionDenied
                    fail(id, permission: permission)
                    // One denial applies to every app. Don't open a tap on the next one.
                    if permission { return }
                }
            }
        }

        func stopAll() {
            for tap in taps.values { tap.stop() }
            taps.removeAll()
        }

        func clearSuppression() { suppressed.removeAll() }
        func unsuppress(_ id: String) { suppressed.remove(id) }

        private func wantsTap(_ level: SavedLevel?) -> Bool {
            guard let level else { return false }
            return level.muted || level.level != 100
        }

        private func gainValue(_ level: SavedLevel?) -> Float {
            guard let level, !level.muted else { return 0 }
            return Float(level.level) / 100
        }

        private func fail(_ id: String, permission: Bool) {
            taps[id]?.stop()
            taps.removeValue(forKey: id)
            suppressed.insert(id)
            onProblem(id, permission)
        }

        /// A tap that never delivers a buffer, or faults, would leave the app silent. Drop it.
        private func scheduleHealthCheck() {
            guard !healthScheduled else { return }
            healthScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.healthScheduled = false
                    self.retireUnhealthy()
                    if self.taps.contains(where: { Date().timeIntervalSince($0.value.createdAt) < 0.8 && !$0.value.healthChecked }) {
                        self.scheduleHealthCheck()
                    }
                }
            }
        }

        private func retireUnhealthy() {
            let now = Date()
            for (id, tap) in Array(taps) {
                guard now.timeIntervalSince(tap.createdAt) >= 0.8, !tap.healthChecked else { continue }
                tap.healthChecked = true
                if tap.hasFault || !tap.didRender { fail(id, permission: false) }
            }
        }
    }
}
