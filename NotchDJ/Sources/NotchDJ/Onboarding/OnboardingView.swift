import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, tour, permission, template, shortcuts, login, done
    var id: Int { rawValue }
}

/// First run, and again from Settings or the notch menu. Styled in the chosen template.
struct OnboardingView: View {
    let finish: @MainActor () -> Void

    @EnvironmentObject private var prefs: DJPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .welcome

    var body: some View {
        let tokens = prefs.tokens
        VStack(spacing: 0) {
            ZStack {
                content
                    .id(step)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 38)
        .padding(.bottom, 22)
        .frame(width: OnboardingWindow.size.width, height: OnboardingWindow.size.height)
        .background(tokens.panel)
        .foregroundStyle(tokens.text)
        .environment(\.djTokens, tokens)
        .environment(\.colorScheme, tokens.isDark ? .dark : .light)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .tour: TourStep()
        case .permission: PermissionStep()
        case .template: TemplateStep()
        case .shortcuts: ShortcutsStep()
        case .login: LoginStep()
        case .done: DoneStep()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            StepDots(step: step)
            Spacer()
            if step != .welcome && step != .done {
                ChipButton(title: String(localized: "Back")) { move(-1) }
            }
            primaryButton
        }
        .frame(height: 30)
    }

    private var primaryButton: some View {
        let title: String
        switch step {
        case .welcome: title = String(localized: "Get Started")
        case .done: title = String(localized: "Start Using Notch DJ")
        default: title = String(localized: "Continue")
        }
        return ChipButton(title: title, prominent: true) {
            if step == .done { finish() } else { move(1) }
        }
        .keyboardShortcut(.defaultAction)
    }

    private func move(_ delta: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + delta) else { return }
        withAnimation(Motion.step) { step = next }
    }
}

private struct StepDots: View {
    let step: OnboardingStep

    @Environment(\.djTokens) private var tokens

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { item in
                Capsule()
                    .fill(item == step ? tokens.accent : tokens.line)
                    .frame(width: item == step ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)"))
    }
}

/// A title and a short paragraph, shared by the steps.
private struct StepHeader: View {
    let title: String
    let message: String

    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(spacing: 8) {
            Text(verbatim: title)
                .font(.system(size: 24, weight: .bold, design: tokens.textDesign))
                .multilineTextAlignment(.center)
            Text(verbatim: message)
                .font(.system(size: 13))
                .foregroundStyle(tokens.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
        }
    }
}

// MARK: Welcome

private struct WelcomeStep: View {
    @Environment(\.djTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 28) {
            NotchIntro(open: shown)
            Wordmark(shown: shown)
            Text("Every app's volume, right in your notch.")
                .font(.system(size: 15))
                .foregroundStyle(tokens.secondary)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.95), value: shown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { shown = true }
    }
}

/// The notch opening into a panel, with three meters coming up inside.
private struct NotchIntro: View {
    let open: Bool

    @Environment(\.djTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            NotchShape(topRadius: open ? 12 : 6, bottomRadius: open ? 26 : 10)
                .fill(Color.black)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array([0.55, 0.85, 0.4, 0.7, 0.5].enumerated()), id: \.offset) { index, level in
                    Capsule()
                        .fill(index == 1 ? tokens.deckA : (index == 3 ? tokens.deckB : Color.white.opacity(0.8)))
                        .frame(width: 8, height: open ? CGFloat(64 * level) : 2)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6)
                            .delay(0.55 + Double(index) * 0.06), value: open)
                }
            }
            .padding(.bottom, 20)
            .opacity(open ? 1 : 0)
        }
        .frame(width: open ? 320 : 120, height: open ? 120 : 28)
        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.78).delay(0.15), value: open)
        .frame(height: 120, alignment: .top)
        .accessibilityHidden(true)
    }
}

private struct Wordmark: View {
    let shown: Bool

    @Environment(\.djTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let letters = Array("NOTCH DJ")

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.letters.enumerated()), id: \.offset) { index, letter in
                Text(verbatim: String(letter))
                    .font(.system(size: 46, weight: .heavy, design: tokens.textDesign))
                    .foregroundStyle(index >= 6 ? tokens.accent : tokens.text)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 14)
                    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7)
                        .delay(0.45 + Double(index) * 0.05), value: shown)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Notch DJ"))
    }
}

// MARK: Tour

private struct TourStep: View {
    var body: some View {
        VStack(spacing: 26) {
            StepHeader(title: String(localized: "Three views, one notch"),
                       message: String(localized: "Click the notch, or press ⌃⌥N. Switch views at the top of the panel."))
            HStack(alignment: .top, spacing: 14) {
                TourCard(symbol: "house", title: PanelTab.home.title,
                         text: String(localized: "What's playing, the master volume and your output. Every app that makes sound, with a meter and mute."))
                TourCard(symbol: "slider.vertical.3", title: PanelTab.mixer.title,
                         text: String(localized: "A fader for every app, with boost above normal volume. Mute, solo, and send an app to its own output."))
                TourCard(symbol: "dial.medium", title: PanelTab.dj.title,
                         text: String(localized: "Two apps on two decks with EQ, filter and a crossfader. Pick a look in Settings."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TourCard: View {
    let symbol: String
    let title: String
    let text: String

    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tokens.accent)
                .frame(height: 28)
            Text(verbatim: title)
                .font(.system(size: 13, weight: .bold, design: tokens.textDesign))
                .tracking(1)
            Text(verbatim: text)
                .font(.system(size: 12))
                .foregroundStyle(tokens.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tokens.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tokens.line, lineWidth: 1))
    }
}

// MARK: Permission

private struct PermissionStep: View {
    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(tokens.accent)
            StepHeader(title: String(localized: "Allow audio access"),
                       message: String(localized: "To change one app's volume, Notch DJ taps that app's audio with Core Audio. macOS calls this System Audio Recording. The audio is processed live on your Mac. It is never recorded, stored or sent anywhere."))
            PermissionStatusRow()
            Text("You can skip this. HOME and the media controls work without it, and Settings › Audio can ask later.")
                .font(.system(size: 11))
                .foregroundStyle(tokens.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Live status of System Audio Recording, with the one button that moves it forward.
struct PermissionStatusRow: View {
    /// Drawn as a card in onboarding, plain inside a Settings form.
    var boxed = true

    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: detail)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            switch permissions.capture {
            case .authorized:
                EmptyView()
            case .denied:
                ChipButton(title: String(localized: "Open System Settings"), prominent: true) {
                    permissions.openCaptureSettings()
                }
            case .notDetermined, .unknown:
                if permissions.usesFallback {
                    ChipButton(title: String(localized: "Got It"), prominent: true) { mixer.acceptExplanation() }
                } else {
                    ChipButton(title: String(localized: "Allow Audio Access"), prominent: true) {
                        permissions.requestCapture()
                    }
                }
            }
        }
        .padding(boxed ? 14 : 0)
        .frame(maxWidth: boxed ? 500 : .infinity)
        .background {
            if boxed { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tokens.surface) }
        }
        .overlay {
            if boxed { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tokens.line, lineWidth: 1) }
        }
        .animation(.easeOut(duration: 0.2), value: permissions.capture)
    }

    private var symbol: String {
        switch permissions.capture {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.octagon.fill"
        case .notDetermined, .unknown: return "circle.dashed"
        }
    }

    private var color: Color {
        switch permissions.capture {
        case .authorized: return tokens.meterLow
        case .denied: return tokens.meterHot
        case .notDetermined, .unknown: return tokens.tertiary
        }
    }

    private var title: String {
        switch permissions.capture {
        case .authorized: return String(localized: "Audio access is on")
        case .denied: return String(localized: "Audio access is off")
        case .notDetermined: return String(localized: "Not asked yet")
        case .unknown: return String(localized: "Checking…")
        }
    }

    private var detail: String {
        switch permissions.capture {
        case .authorized:
            return String(localized: "Faders, decks and meters are ready.")
        case .denied:
            return String(localized: "Turn on Notch DJ in Privacy & Security › Screen & System Audio Recording. This updates by itself.")
        case .notDetermined, .unknown:
            if permissions.usesFallback {
                return String(localized: "macOS asks the first time you change an app's volume.")
            }
            return String(localized: "macOS shows its prompt once. Notch DJ remembers the answer.")
        }
    }
}

// MARK: Template

private struct TemplateStep: View {
    @EnvironmentObject private var prefs: DJPreferences

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(title: String(localized: "Pick a look"),
                       message: String(localized: "Every template has the same controls. Change it any time from the panel or Settings."))
            HStack(alignment: .top, spacing: 18) {
                ScrollView(.vertical, showsIndicators: false) {
                    TemplateGrid()
                }
                .frame(width: 220)
                VStack(spacing: 10) {
                    TemplatePreview(id: prefs.template, width: 360)
                    if prefs.template.template.supportsLight && prefs.template.template.supportsDark {
                        Picker("Appearance", selection: $prefs.appearance) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(verbatim: mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: Shortcuts

private struct ShortcutsStep: View {
    @ObservedObject private var hotkeys = DJHotkeys.shared
    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(tokens.accent)
            StepHeader(title: String(localized: "Keyboard shortcuts"),
                       message: String(localized: "They work from any app. Notch DJ doesn't need Accessibility for them."))
            VStack(spacing: 10) {
                ShortcutRow(keys: "⌃⌥N", text: String(localized: "Open or close the panel"))
                ShortcutRow(keys: "⌃⌥M", text: String(localized: "Open MIXER, then switch between MIXER and DJ"))
            }
            .frame(maxWidth: 440)
            Toggle(isOn: Binding(get: { hotkeys.isEnabled }, set: { hotkeys.setEnabled($0) })) {
                Text("Use global shortcuts")
            }
            .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShortcutRow: View {
    let keys: String
    let text: String

    @Environment(\.djTokens) private var tokens

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: keys)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .frame(minWidth: 70, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tokens.raised))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tokens.line, lineWidth: 1))
            Text(verbatim: text)
                .font(.system(size: 13))
            Spacer(minLength: 0)
        }
    }
}

// MARK: Login

private struct LoginStep: View {
    @EnvironmentObject private var prefs: DJPreferences
    @Environment(\.djTokens) private var tokens
    @State private var enabled = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "power")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(tokens.accent)
            StepHeader(title: String(localized: "Start with your Mac"),
                       message: String(localized: "Notch DJ uses almost no energy while the panel is closed."))
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(get: { enabled }, set: { setLogin($0) })) {
                    Text("Open Notch DJ at login")
                }
                .toggleStyle(.switch)
                if needsApproval {
                    HStack(spacing: 8) {
                        Text("macOS needs your OK in Login Items.")
                            .font(.system(size: 11))
                            .foregroundStyle(tokens.secondary)
                        ChipButton(title: String(localized: "Open Login Items")) { LoginItem.openSettings() }
                    }
                }
                Toggle(isOn: $prefs.openOnHover) {
                    Text("Open the panel when the pointer rests on the notch")
                }
                .toggleStyle(.switch)
            }
            .frame(maxWidth: 440, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setLogin(_ on: Bool) {
        LoginItem.set(on)
        enabled = LoginItem.isEnabled
        needsApproval = LoginItem.needsApproval
    }
}

// MARK: Done

private struct DoneStep: View {
    @EnvironmentObject private var permissions: PermissionCenter
    @Environment(\.djTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(tokens.accent)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6), value: shown)
            StepHeader(title: String(localized: "You're all set"),
                       message: permissions.capture == .authorized
                           ? String(localized: "Click the notch or press ⌃⌥N. Right-click the notch for Settings.")
                           : String(localized: "Click the notch or press ⌃⌥N. Faders ask for audio access the first time you move them."))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { shown = true }
    }
}
