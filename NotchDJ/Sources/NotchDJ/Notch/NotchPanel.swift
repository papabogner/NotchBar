// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import AppKit
import SwiftUI

/// A borderless panel pinned over the notch. It stays out of the keyboard until a text
/// field is showing, so opening the notch does not pull you out of another app.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // DJWindow switches this to match the template, so menus and system controls follow it.
        appearance = NSAppearance(named: .darkAqua)
    }

    /// True only while a text field in the notch needs the keyboard. A normal open stays non-key.
    var allowsTyping = false {
        didSet { becomesKeyOnlyIfNeeded = !allowsTyping }
    }

    override var canBecomeKey: Bool { allowsTyping }
    override var canBecomeMain: Bool { allowsTyping }
}

/// Lets the first click act on a control instead of only activating the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
