import Combine
import SwiftUI

/// The notch's only job: closed line, or the mixer.
@MainActor
final class DJModel: ObservableObject {
    @Published var isExpanded = false
    @Published var isHovering = false
    @Published var geometry = NotchGeometry.fallback
    @Published var openOnHover = true
    let mixer: AppVolumeMixer
    let now: NowPlayingMonitor
    private var cancellables: Set<AnyCancellable> = []

    init(mixer: AppVolumeMixer, now: NowPlayingMonitor) {
        self.mixer = mixer
        self.now = now
        openOnHover = DJDefaults.suite.object(forKey: "openOnHover") as? Bool ?? true
        mixer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        now.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    var leftWing: CGFloat {
        guard let entry = now.entry, entry.isPlaying, !isExpanded else { return 0 }
        return 220
    }

    var collapsedSize: CGSize {
        CGSize(width: geometry.notchWidth + leftWing + 12, height: geometry.notchHeight)
    }

    var expandedSize: CGSize {
        let content: CGFloat = mixer.face == .dj ? 500 : 430
        return CGSize(width: 760, height: geometry.notchHeight + content)
    }

    var size: CGSize { isExpanded ? expandedSize : collapsedSize }
    var shapeOffset: CGFloat { isExpanded ? 0 : -leftWing / 2 }
    var topRadius: CGFloat { isExpanded ? 16 : 6 }
    var bottomRadius: CGFloat { isExpanded ? 22 : 10 }

    func open() {
        isExpanded = true
        mixer.setSurfaces(mixerTab: true, home: false)
    }

    func close() {
        isExpanded = false
        mixer.setSurfaces(mixerTab: false, home: false)
    }

    func toggle() {
        isExpanded ? close() : open()
    }

    /// ⌃⌥M. Opens the mixer, or flips MIXER / DJ when it is already open.
    func mixerKey() {
        if !isExpanded {
            open()
            return
        }
        mixer.face = mixer.face == .mixer ? .dj : .mixer
    }

    func setOpenOnHover(_ on: Bool) {
        openOnHover = on
        DJDefaults.suite.set(on, forKey: "openOnHover")
    }
}
