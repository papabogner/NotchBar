import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
}

/// Where the menu bar icon shows. Automatic means only on screens without a notch.
enum MenuBarMode: String, CaseIterable, Identifiable, Sendable {
    case automatic, always, never
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return String(localized: "Without a notch")
        case .always: return String(localized: "Always")
        case .never: return String(localized: "Never")
        }
    }
}

/// Look and behaviour settings, stored in Notch DJ's defaults suite.
@MainActor
final class DJPreferences: ObservableObject {
    private enum Key {
        static let panelSize = "panelSize"
        static let template = "template"
        static let appearance = "appearance"
        static let openOnHover = "openOnHover"
        static let menuBarMode = "menuBarMode"
        static let mediaKeys = "mediaKeys"
        static let onboarding = "onboardingCompleted"
    }

    @Published var panelSize: PanelSize {
        didSet { store(panelSize.rawValue, Key.panelSize) }
    }
    @Published var template: TemplateID {
        didSet { store(template.rawValue, Key.template) }
    }
    @Published var appearance: AppearanceMode {
        didSet { store(appearance.rawValue, Key.appearance) }
    }
    @Published var openOnHover: Bool {
        didSet { store(openOnHover, Key.openOnHover) }
    }
    @Published var menuBarMode: MenuBarMode {
        didSet { store(menuBarMode.rawValue, Key.menuBarMode) }
    }
    /// Transport for apps that can't be scripted sends the system media keys. Needs Accessibility.
    @Published var mediaKeys: Bool {
        didSet { store(mediaKeys, Key.mediaKeys) }
    }
    @Published var onboardingCompleted: Bool {
        didSet { store(onboardingCompleted, Key.onboarding) }
    }
    @Published private(set) var systemIsDark: Bool

    private let isPreview: Bool
    private var appearanceObservation: NSKeyValueObservation?

    init(preview: TemplateID? = nil, dark: Bool = true) {
        let suite = DJDefaults.suite
        if let preview {
            isPreview = true
            panelSize = .regular
            template = preview
            appearance = dark ? .dark : .light
            openOnHover = true
            menuBarMode = .automatic
            mediaKeys = false
            onboardingCompleted = true
            systemIsDark = dark
            return
        }
        isPreview = false
        panelSize = PanelSize(rawValue: suite.string(forKey: Key.panelSize) ?? "") ?? .regular
        template = TemplateID(rawValue: suite.string(forKey: Key.template) ?? "") ?? .studio
        appearance = AppearanceMode(rawValue: suite.string(forKey: Key.appearance) ?? "") ?? .system
        openOnHover = suite.object(forKey: Key.openOnHover) as? Bool ?? true
        menuBarMode = MenuBarMode(rawValue: suite.string(forKey: Key.menuBarMode) ?? "") ?? .automatic
        mediaKeys = suite.object(forKey: Key.mediaKeys) as? Bool ?? false
        onboardingCompleted = suite.bool(forKey: Key.onboarding)
        systemIsDark = Self.readSystemDark()
        let prefs = self
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            // AppKit changes the appearance on the main thread.
            MainActor.assumeIsolated { prefs.systemAppearanceChanged() }
        }
    }

    /// Light or dark after the template's limits and the appearance setting.
    var isDark: Bool {
        let current = template.template
        if !current.supportsLight { return true }
        if !current.supportsDark { return false }
        switch appearance {
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        }
    }

    var tokens: ThemeTokens { template.template.tokens(dark: isDark) }

    func tokens(for id: TemplateID) -> ThemeTokens {
        let candidate = id.template
        let dark: Bool
        if !candidate.supportsLight {
            dark = true
        } else if !candidate.supportsDark {
            dark = false
        } else {
            switch appearance {
            case .system: dark = systemIsDark
            case .light: dark = false
            case .dark: dark = true
            }
        }
        return candidate.tokens(dark: dark)
    }

    private func systemAppearanceChanged() {
        let dark = Self.readSystemDark()
        if dark != systemIsDark { systemIsDark = dark }
    }

    private static func readSystemDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func store(_ value: Any, _ key: String) {
        guard !isPreview else { return }
        DJDefaults.suite.set(value, forKey: key)
    }
}
