import AppKit
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable, Sendable {
    case home, mixer, dj
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return String(localized: "HOME")
        case .mixer: return String(localized: "MIXER")
        case .dj: return String(localized: "DJ")
        }
    }

    var order: Int {
        switch self {
        case .home: return 0
        case .mixer: return 1
        case .dj: return 2
        }
    }
}

/// Sizes of the closed notch. See docs/DESIGN.md, "Sizes".
enum NotchStyle {
    static let closedTop: CGFloat = 6
    static let closedBottom: CGFloat = 10
    static let openTop: CGFloat = 14
    static let wing: CGFloat = 34
    static let hoverGrow: CGFloat = 12
    static let hoverDrop: CGFloat = 3
}

/// Open or closed, which tab, and how big. The panel views observe this, the mixer, now
/// playing and the preferences separately, so a change in one doesn't redraw the others.
@MainActor
final class DJModel: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published var isHovering = false
    @Published var geometry = NotchGeometry.fallback
    @Published var screenSize = CGSize(width: 1512, height: 982)
    /// Kept for the session, so the panel reopens where you left it. HOME at launch.
    @Published private(set) var tab: PanelTab = .home
    /// +1 when the new tab is to the right of the old one, for the slide.
    @Published private(set) var tabDirection: CGFloat = 1
    /// The MIXER strip to point out after a click on HOME.
    @Published var highlightedStrip: String?
    /// No notch on this screen and the menu bar icon is showing, so the pill isn't drawn.
    @Published var hidesPill = false

    /// A menu from the panel is open. The panel stays open while it tracks.
    var menuOpen = false

    let mixer: AppVolumeMixer
    let now: NowPlayingMonitor
    let prefs: DJPreferences
    let permissions: PermissionCenter

    var onShowSettings: (@MainActor () -> Void)?
    var onShowOnboarding: (@MainActor () -> Void)?

    init(mixer: AppVolumeMixer, now: NowPlayingMonitor, prefs: DJPreferences, permissions: PermissionCenter) {
        self.mixer = mixer
        self.now = now
        self.prefs = prefs
        self.permissions = permissions
    }

    var metrics: PanelMetrics {
        PanelMetrics.make(prefs.panelSize, screen: screenSize, notchHeight: geometry.notchHeight)
    }

    /// Artwork and a level mark beside a closed notch, while Music or Spotify plays.
    var showsWings: Bool {
        !isExpanded && !hidesPill && now.entry?.isPlaying == true
    }

    /// The shape's size. Closed and idle, its body is exactly the hardware notch.
    var size: CGSize {
        if isExpanded {
            let metrics = metrics
            return CGSize(width: metrics.width, height: metrics.height)
        }
        if hidesPill { return CGSize(width: geometry.notchWidth, height: 0) }
        let wings = showsWings ? NotchStyle.wing * 2 : 0
        let grow = isHovering ? NotchStyle.hoverGrow * 2 : 0
        return CGSize(width: geometry.notchWidth + NotchStyle.closedTop * 2 + wings + grow,
                      height: geometry.notchHeight + (isHovering ? NotchStyle.hoverDrop : 0))
    }

    // MARK: Open and close

    func open(_ tab: PanelTab? = nil) {
        if let tab { select(tab, animated: isExpanded) }
        guard !isExpanded else { return }
        withAnimation(Motion.openClose) {
            isExpanded = true
            isHovering = false
        }
        let playing = now.entry?.isPlaying == true ? now.entry?.source.bundleID : nil
        mixer.setPreferredDeckApp(playing)
        mixer.setPanelVisible(true)
        permissions.refresh()
        now.refresh()
    }

    func close() {
        guard isExpanded else { return }
        withAnimation(Motion.openClose) {
            isExpanded = false
        }
        highlightedStrip = nil
        mixer.setPanelVisible(false)
    }

    func toggle() {
        isExpanded ? close() : open()
    }

    /// ⌃⌥M. Opens MIXER, or flips between MIXER and DJ when the panel is open.
    func mixerKey() {
        guard isExpanded else {
            open(.mixer)
            return
        }
        select(tab == .mixer ? .dj : .mixer)
    }

    func select(_ next: PanelTab, animated: Bool = true) {
        guard next != tab else { return }
        tabDirection = next.order > tab.order ? 1 : -1
        if next != .mixer { highlightedStrip = nil }
        if animated {
            withAnimation(Motion.tab) { tab = next }
        } else {
            tab = next
        }
    }

    /// From a HOME card: MIXER with that strip pointed out.
    func showStrip(_ id: String) {
        highlightedStrip = id
        select(.mixer)
    }

    // MARK: Permission

    /// The banner's Allow button. Asks macOS once; after a refusal it opens System Settings.
    /// Without the private request call, the next tap shows the system prompt instead.
    func allowCapture() {
        switch permissions.capture {
        case .authorized:
            mixer.acceptExplanation()
        case .denied:
            permissions.openCaptureSettings()
        case .notDetermined, .unknown:
            if permissions.usesFallback {
                mixer.acceptExplanation()
            } else {
                permissions.requestCapture()
            }
        }
    }

    func showSettings() { onShowSettings?() }
    func showOnboarding() { onShowOnboarding?() }
}
