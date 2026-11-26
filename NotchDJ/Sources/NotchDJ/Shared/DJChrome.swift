import SwiftUI

/// Enough of the old notch chrome for the unused home-style fader still in MixerPanel.
struct DJChrome {
    enum FaderStyle { case line, pill, tall }
    var faderStyle: FaderStyle = .pill
    var accent: Color = TEColor.accent
    var faderWidthScale: CGFloat = 1
}

private struct DJChromeKey: EnvironmentKey {
    static let defaultValue = DJChrome()
}

extension EnvironmentValues {
    var notchChrome: DJChrome {
        get { self[DJChromeKey.self] }
        set { self[DJChromeKey.self] = newValue }
    }
}
