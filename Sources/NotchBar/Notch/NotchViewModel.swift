import SwiftUI
import Combine
import ApplicationServices

/// The notch's state: which tab is open, what banner is showing, and how big the shape is.
@MainActor
final class NotchViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case home, media, claude, timer, clipboard, calendar, activity, mixer
        var id: String { rawValue }
        var title: String { rawValue == "claude" ? "Claude" : rawValue.capitalized }

        /// The tabs that existed before tab preferences were saved, so a tab added later
        /// shows up for everyone once instead of staying hidden by an old preference.
        static let original: [Tab] = [.home, .media, .claude, .timer, .clipboard, .calendar]

        /// Mixer uses process taps, which need macOS 14.4. It isn't offered before that.
        static var offered: [Tab] {
            if #available(macOS 14.4, *) { return allCases }
            return allCases.filter { $0 != .mixer }
        }
    }

    /// A small drop-down below the closed notch, like a Live Activity.
    enum Banner: Equatable {
        case nowPlaying
        case hud(HUDState)
        case timerDone
        case meeting(CalendarEvent)
        case device(DeviceEvent)
        case agent(String)

        /// A banner never replaces one with a higher priority.
        var priority: Int {
            switch self {
            case .nowPlaying: return 0
            case .hud: return 1
            // A device switching restores its saved volume, which reports a volume change,
            // so a device outranks the volume HUD that would otherwise replace it at once.
            case .device: return 2
            case .timerDone, .meeting, .agent: return 3
            }
        }

        var duration: TimeInterval {
            switch self {
            case .nowPlaying: return 3.2
            case .hud: return 1.6
            case .device(let event): return event.connected ? 5 : 3.5
            case .meeting: return 20
            case .agent: return 6
            case .timerDone: return 30
            }
        }

        var isHUD: Bool { if case .hud = self { return true } else { return false } }
        var isDevice: Bool { if case .device = self { return true } else { return false } }
    }

    @Published var isExpanded = false
    @Published var isHovering = false
    @Published var tab: Tab = .home
    @Published var geometry = NotchGeometry.fallback
    @Published var isMenuOpen = false
    @Published private(set) var banner: Banner?
    @Published private(set) var toast: String?
    @Published private(set) var enabledTabs: [Tab]
    /// Opened from the keyboard: stays open until the pointer visits or a click lands elsewhere.
    @Published var isSticky = false
    /// The camera glance from the header's camera button. It replaces the tab's content and
    /// turns off whenever the notch closes or another tab is picked.
    @Published private(set) var showsCamera = false
    /// Leaves the notch out of screenshots, screen recordings and screen sharing.
    @Published var hideFromScreenshots: Bool { didSet { UserDefaults.standard.set(hideFromScreenshots, forKey: "hideFromScreenshots") } }
    /// Hovering the closed notch opens it after a short pause. Click still opens at once.
    @Published var openOnHover: Bool { didSet { UserDefaults.standard.set(openOnHover, forKey: "openOnHover") } }
    /// That hover-open shows the Mixer tab.
    @Published var mixerOnHover: Bool { didSet { UserDefaults.standard.set(mixerOnHover, forKey: "mixerOnHover") } }

    let media: MediaController
    let usage: ClaudeUsageStore
    let timer: TimerModel
    let hudService: HUDService
    let clipboard: ClipboardStore
    let calendar: CalendarStore
    let weather: WeatherStore
    let dictation: DictationMonitor
    let activity: ActivityMonitor
    let volumes: AppVolumeMixer
    let homeLayout = HomeLayout()
    let appearance = NotchAppearance()
    let ticker: TickerStore
    let agents = AgentMonitor()
    @Published var showsAppearance = false
    @Published var showsTickerSettings = false
    let camera = CameraGlance()

    static let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.76)
    static let closeSpring = Animation.spring(response: 0.36, dampingFraction: 0.95)

    private var bannerWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    init(media: MediaController, usage: ClaudeUsageStore, timer: TimerModel, hudService: HUDService,
         clipboard: ClipboardStore, calendar: CalendarStore, weather: WeatherStore, dictation: DictationMonitor,
         activity: ActivityMonitor, volumes: AppVolumeMixer? = nil) {
        self.weather = weather
        self.dictation = dictation
        self.activity = activity
        let mixer = volumes ?? AppVolumeMixer()
        self.volumes = mixer
        hideFromScreenshots = UserDefaults.standard.bool(forKey: "hideFromScreenshots")
        openOnHover = UserDefaults.standard.object(forKey: "openOnHover") as? Bool ?? true
        mixerOnHover = UserDefaults.standard.object(forKey: "mixerOnHover") as? Bool ?? true
        self.media = media
        self.usage = usage
        self.timer = timer
        self.hudService = hudService
        self.clipboard = clipboard
        self.calendar = calendar
        ticker = TickerStore(media: media, calendar: calendar, usage: usage)
        agents.onAlert = { [weak self] text in self?.show(.agent(text)) }
        agents.onLine = { [weak self] line in self?.ticker.agentLine = line }
        enabledTabs = Self.loadEnabledTabs()

        // The closed notch's width depends on the timer and on playback, so redraw with them.
        timer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        media.$nowPlaying.map { $0?.isPlaying == true }.removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        dictation.$listening.removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        timer.onFinish = { [weak self] in self?.timerFinished() }
        hudService.present = { [weak self] state in self?.show(.hud(state)) }
        hudService.presentDevice = { [weak self] event in self?.show(.device(event)) }
        calendar.onMeetingSoon = { [weak self] event in
            guard self?.isEnabled(.calendar) == true else { return }
            self?.show(.meeting(event))
        }
        // Activity is only measured while someone can see it.
        Publishers.CombineLatest($isExpanded, $tab)
            .sink { [weak self] expanded, tab in
                guard let self else { return }
                activity.setActive(expanded && (tab == .activity || (tab == .home && self.isEnabled(.activity))))
            }
            .store(in: &bag)
        // The camera runs only while its preview can be seen.
        Publishers.CombineLatest($isExpanded, $showsCamera)
            .sink { [weak self] expanded, showsCamera in
                guard let self else { return }
                if !expanded && showsCamera { self.showsCamera = false }
                self.camera.setActive(expanded && showsCamera)
            }
            .store(in: &bag)
        // The mixer list follows playback while its tab or the Home strips are showing.
        // Moving a slider is what starts a tap; opening the tab does not.
        mixer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        homeLayout.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.updateAgentWatch()
        }.store(in: &bag)
        appearance.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        ticker.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.updateAgentWatch()
        }.store(in: &bag)
        agents.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        updateAgentWatch()
        Publishers.CombineLatest3($isExpanded, $tab, $showsCamera)
            .sink { [weak self] _, _, _ in self?.refreshMixerSurfaces() }
            .store(in: &bag)
        media.onNeedsAccessibility = { [weak self] app in
            self?.showToast("Allow NotchBar in Privacy & Security > Accessibility to control \(app).")
        }
        // A new song peeks below the notch for a moment.
        media.$nowPlaying
            .map { $0.flatMap { $0.isPlaying ? $0.trackID : nil } }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] id in
                guard id != nil else { return }
                MainActor.assumeIsolated { self?.show(.nowPlaying) }
            }
            .store(in: &bag)
        clipboard.isEnabled = isEnabled(.clipboard)
        if !enabledTabs.contains(tab) { tab = enabledTabs[0] }
    }

    /// The saved tab choice, plus any tab that didn't exist when it was saved.
    private static func loadEnabledTabs() -> [Tab] {
        let defaults = UserDefaults.standard
        defer { defaults.set(Tab.offered.map(\.rawValue), forKey: "knownTabs") }
        let decoded = defaults.stringArray(forKey: "enabledTabs")?.compactMap(Tab.init(rawValue:)) ?? []
        let saved = decoded.filter { Tab.offered.contains($0) }
        guard !saved.isEmpty else { return Tab.offered }
        let known = Set((defaults.stringArray(forKey: "knownTabs") ?? Tab.original.map(\.rawValue)).compactMap(Tab.init(rawValue:)))
        let added = Tab.offered.filter { !known.contains($0) }
        guard !added.isEmpty else { return saved }
        let tabs = Tab.offered.filter { saved.contains($0) || added.contains($0) }
        defaults.set(tabs.map(\.rawValue), forKey: "enabledTabs")
        return tabs
    }

    // MARK: Shape

    /// The closed notch only extends as far as its content, so it covers as little of the
    /// menu bar as possible: nothing on the left unless music plays or a timer runs.
    var leftWing: CGFloat {
        if dictation.listening != nil { return 58 }
        if timer.isActive && isEnabled(.timer) { return 76 }
        if ticker.shows { return min(280, max(120, ticker.width)) }
        return media.nowPlaying?.isPlaying == true && isEnabled(.media) ? 38 : 0
    }
    var rightWing: CGFloat { isEnabled(.claude) ? 30 : 0 }

    /// Moves a lopsided closed notch so it stays anchored to the camera housing.
    var shapeOffset: CGFloat {
        isExpanded || banner != nil ? 0 : (rightWing - leftWing) / 2
    }

    var topRadius: CGFloat { isExpanded ? 16 : 6 }
    var bottomRadius: CGFloat { isExpanded ? 30 : (banner == nil ? 10 : 20) }

    var collapsedSize: CGSize { CGSize(width: geometry.notchWidth + leftWing + rightWing + 12, height: geometry.notchHeight) }
    var bannerSize: CGSize {
        let base = geometry.notchWidth + 2 * max(leftWing, rightWing) + 12
        if banner?.isHUD == true { return CGSize(width: max(base + 40, 320), height: geometry.notchHeight + 38) }
        if case .device(let event) = banner {
            return CGSize(width: max(base + 90, 390), height: geometry.notchHeight + (event.battery.isEmpty ? 58 : 108))
        }
        // Snooze, Join and Dismiss sit side by side, so a meeting needs the room.
        if case .meeting = banner { return CGSize(width: max(base + 120, 420), height: geometry.notchHeight + 50) }
        return CGSize(width: max(base + 70, 340), height: geometry.notchHeight + 50)
    }

    var expandedSize: CGSize {
        let content: CGFloat
        switch tab {
        case _ where showsCamera: content = 262
        case .home: content = 346
        case .calendar, .activity: content = 222
        case .mixer: content = 300
        default: content = 150
        }
        // A toast gets its own strip below the content instead of covering it.
        return CGSize(width: 720, height: geometry.notchHeight + content + (toast == nil ? 0 : 30))
    }

    var size: CGSize {
        if isExpanded { return expandedSize }
        if banner != nil { return bannerSize }
        let c = collapsedSize
        return isHovering ? CGSize(width: c.width + 12, height: c.height + 3) : c
    }

    // MARK: Tabs

    func isEnabled(_ tab: Tab) -> Bool { enabledTabs.contains(tab) }

    /// Shows or hides a tab. At least one stays visible.
    func setEnabled(_ tab: Tab, _ enabled: Bool) {
        var tabs = enabledTabs
        if enabled { tabs = Tab.offered.filter { tabs.contains($0) || $0 == tab } } else { tabs.removeAll { $0 == tab } }
        guard !tabs.isEmpty else { return }
        enabledTabs = tabs
        UserDefaults.standard.set(tabs.map(\.rawValue), forKey: "enabledTabs")
        clipboard.isEnabled = isEnabled(.clipboard)
        if !tabs.contains(self.tab) { self.tab = tabs[0] }
        activity.setActive(isExpanded && (self.tab == .activity || (self.tab == .home && isEnabled(.activity))))
        refreshMixerSurfaces()
    }

    private func updateAgentWatch() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wants = self.homeLayout.isEnabled(.agents)
                    || (self.ticker.isEnabled && self.ticker.sources.contains(.agents))
                self.agents.setActive(wants)
            }
        }
    }

    /// The mixer list is live on its own tab, and on Home only while the combined panel is on.
    func refreshMixerSurfaces() {
        let mixerTab = isExpanded && tab == .mixer && !showsCamera
        let home = isExpanded && tab == .home && !showsCamera && isEnabled(.mixer) && homeLayout.isEnabled(.mixer)
        volumes.setSurfaces(mixerTab: mixerTab, home: home)
    }

    /// The tab to open from the middle of the notch: Home, or the first visible tab.
    var preferredTab: Tab { isEnabled(.home) ? .home : enabledTabs[0] }

    // MARK: Opening and closing

    func open(_ tab: Tab) {
        let target = isEnabled(tab) ? tab : enabledTabs[0]
        if target == .media || target == .home { media.refresh(discover: true) }
        if banner == .timerDone { timer.dismissAlert() }
        bannerWork?.cancel()
        withAnimation(Self.openSpring) {
            self.tab = target
            showsCamera = false
            banner = nil
            isExpanded = true
        }
    }

    func select(_ tab: Tab) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            self.tab = tab
            showsCamera = false
        }
    }

    /// The header's camera button: a quick look in the camera, or back to the tab.
    func toggleCamera() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { showsCamera.toggle() }
    }

    func close() {
        isSticky = false
        withAnimation(Self.closeSpring) {
            isExpanded = false
            showsCamera = false
            showsAppearance = false
            showsTickerSettings = false
        }
    }

    /// ⌃⌘V: show the clipboard, or hide it if it's already showing.
    func toggleClipboard() {
        guard isEnabled(.clipboard) else { return }
        if isExpanded && tab == .clipboard { close(); return }
        open(.clipboard)
        isSticky = true
    }

    // MARK: Banners

    func show(_ new: Banner) {
        guard !isExpanded else {
            if new == .timerDone && isEnabled(.timer) { select(.timer) }
            // A reminder still reaches you while the notch is open, as a line at the bottom.
            if case .meeting(let event) = new {
                let minutes = Int(ceil(event.start.timeIntervalSinceNow / 60))
                showToast(minutes > 0 ? "\(event.title) starts in \(minutes) min" : "\(event.title) is starting now")
            }
            if case .agent(let text) = new { showToast(text) }
            return
        }
        // While a device banner shows, a volume change updates its volume instead.
        if case .device(var event) = banner, case .hud(let state) = new {
            if state.kind == .volume, event.connected {
                event.volume = state.muted ? 0 : state.value
                banner = .device(event)
            }
            return
        }
        if let current = banner, current.priority > new.priority { return }
        let sameKind = (banner?.isHUD == true && new.isHUD) || (banner?.isDevice == true && new.isDevice)
        withAnimation(sameKind ? .spring(response: 0.25, dampingFraction: 0.85)
                               : (new == .timerDone ? .spring(response: 0.38, dampingFraction: 0.55) : Self.openSpring)) {
            banner = new
        }
        scheduleBannerHide(after: new.duration)
    }

    func dismissBanner() {
        bannerWork?.cancel()
        if banner == .timerDone { timer.dismissAlert() }
        withAnimation(Self.closeSpring) { banner = nil }
    }

    private func scheduleBannerHide(after delay: TimeInterval) {
        bannerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A HUD stays while the pointer is on it, so its bar can be dragged.
                if self.isHovering && self.banner?.isHUD == true { self.scheduleBannerHide(after: 1); return }
                self.dismissBanner()
            }
        }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func timerFinished() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        show(.timerDone)
    }

    // MARK: Clipboard

    func copyClip(_ item: ClipItem, paste: Bool) {
        clipboard.copy(item)
        guard paste else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                MainActor.assumeIsolated { if self?.isSticky == true { self?.close() } }
            }
            return
        }
        guard AXIsProcessTrusted() else {
            MediaKeyTap.requestTrust()
            showToast("Copied. Allow NotchBar in Accessibility to paste directly.")
            return
        }
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { PasteKey.post() }
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { toast = text }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil } }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }
}
