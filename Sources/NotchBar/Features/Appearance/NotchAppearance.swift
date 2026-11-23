import AppKit
import SwiftUI

/// How the notch is painted. Closed, it stays black so it matches the hardware.
@MainActor
final class NotchAppearance: ObservableObject {
    struct Theme: Equatable, Codable {
        enum Preset: String, Codable, CaseIterable, Identifiable {
            case classic, glass, neon, console, custom
            var id: String { rawValue }
            var title: String {
                switch self {
                case .classic: return "Classic"
                case .glass: return "Glass"
                case .neon: return "Neon"
                case .console: return "Console"
                case .custom: return "Custom"
                }
            }
        }

        var preset: Preset = .classic
        var accentR = 1.0, accentG = 1.0, accentB = 1.0
        var bgR = 0.0, bgG = 0.0, bgB = 0.0
        var bg2R = 0.12, bg2G = 0.12, bg2B = 0.14
        var angle = 90.0
        var albumColors = false

        static let classic = Theme()
        static let glass = Theme(preset: .glass, accentR: 0.75, accentG: 0.88, accentB: 1)
        static let neon = Theme(preset: .neon, accentR: 0.2, accentG: 1, accentB: 0.65, bgR: 0.02, bgG: 0.04, bgB: 0.05, bg2R: 0.0, bg2G: 0.18, bg2B: 0.12, angle: 120)
        static let console = Theme(preset: .console, accentR: 1, accentG: 0.55, accentB: 0.2, bgR: 0.09, bgG: 0.07, bgB: 0.05, bg2R: 0.16, bg2G: 0.11, bg2B: 0.07, angle: 180)

        var accent: Color { Color(red: accentR, green: accentG, blue: accentB) }
        var background: Color { Color(red: bgR, green: bgG, blue: bgB) }
        var backgroundEnd: Color { Color(red: bg2R, green: bg2G, blue: bg2B) }
        var faderCorner: CGFloat { preset == .console ? 8 : 18 }
    }

    @Published var theme: Theme {
        didSet { persist() }
    }

    private static let key = "notchTheme"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Theme.self, from: data) {
            theme = saved
        } else {
            theme = .classic
        }
    }

    func apply(_ preset: Theme.Preset) {
        switch preset {
        case .classic: theme = .classic
        case .glass: theme = .glass
        case .neon: theme = .neon
        case .console: theme = .console
        case .custom:
            var next = theme
            next.preset = .custom
            theme = next
        }
    }

    func setAccent(_ color: Color) {
        let parts = Self.components(color)
        var next = theme
        next.preset = .custom
        next.accentR = parts.r
        next.accentG = parts.g
        next.accentB = parts.b
        theme = next
    }

    func setBackground(_ color: Color, end: Bool) {
        let parts = Self.components(color)
        var next = theme
        next.preset = .custom
        if end {
            next.bg2R = parts.r; next.bg2G = parts.g; next.bg2B = parts.b
        } else {
            next.bgR = parts.r; next.bgG = parts.g; next.bgB = parts.b
        }
        theme = next
    }

    /// Accent and background drawn from the current artwork when Album colors is on.
    func displayed(album: NSColor?) -> Theme {
        guard theme.albumColors, let album, let rgb = album.usingColorSpace(.sRGB) else { return theme }
        var next = theme
        next.accentR = Double(rgb.redComponent)
        next.accentG = Double(rgb.greenComponent)
        next.accentB = Double(rgb.blueComponent)
        next.bgR = next.accentR * 0.18
        next.bgG = next.accentG * 0.18
        next.bgB = next.accentB * 0.18
        next.bg2R = next.accentR * 0.45
        next.bg2G = next.accentG * 0.45
        next.bg2B = next.accentB * 0.45
        return next
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(theme), forKey: Self.key)
    }

    private static func components(_ color: Color) -> (r: Double, g: Double, b: Double) {
        let resolved = color.resolve(in: EnvironmentValues())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }
}

private struct NotchChromeKey: EnvironmentKey {
    static let defaultValue = NotchAppearance.Theme.classic
}

extension EnvironmentValues {
    var notchChrome: NotchAppearance.Theme {
        get { self[NotchChromeKey.self] }
        set { self[NotchChromeKey.self] = newValue }
    }
}

struct NotchMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
