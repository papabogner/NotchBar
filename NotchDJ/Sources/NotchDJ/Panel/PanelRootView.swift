import AppKit
import SwiftUI

private struct HeroNamespaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID? { nil }
}

extension EnvironmentValues {
    /// Shared by HOME and DJ so the playing artwork moves between them.
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func hero(_ id: String, _ namespace: Namespace.ID?, enabled: Bool = true) -> some View {
        if let namespace, enabled {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

/// The whole notch window: the closed notch or the open panel, in the chosen template.
struct PanelRootView: View {
    @ObservedObject var model: DJModel
    @ObservedObject var prefs: DJPreferences

    var body: some View {
        let tokens = prefs.tokens
        VStack(spacing: 0) {
            NotchBody()
            Spacer(minLength: 0)
        }
        .frame(width: DJWindow.canvas.width, height: DJWindow.canvas.height, alignment: .top)
        .environment(\.djTokens, tokens)
        .environment(\.panelMetrics, model.metrics)
        .environment(\.colorScheme, tokens.isDark ? .dark : .light)
    }
}

private struct NotchBody: View {
    @EnvironmentObject private var model: DJModel
    /// The closed size depends on whether something plays.
    @EnvironmentObject private var now: NowPlayingMonitor
    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics

    var body: some View {
        let size = model.size
        let expanded = model.isExpanded
        let shape = NotchShape(
            topRadius: expanded ? NotchStyle.openTop : NotchStyle.closedTop,
            bottomRadius: expanded ? tokens.panelRadius : (model.isHovering ? 12 : NotchStyle.closedBottom)
        )
        ZStack(alignment: .top) {
            if expanded {
                ExpandedPanel()
                    .frame(width: metrics.width, height: metrics.height, alignment: .top)
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
            } else if !model.hidesPill {
                ClosedNotch()
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .shadow(color: .black.opacity(expanded ? 0.32 : 0), radius: 18, y: 10)
        .contentShape(shape)
    }
}

/// Black and still. With Music or Spotify playing, artwork on the left and a level mark on the right.
private struct ClosedNotch: View {
    @EnvironmentObject private var model: DJModel
    @EnvironmentObject private var now: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 0) {
            if model.showsWings {
                Group {
                    if let artwork = now.artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AppIconView(bundleID: now.entry?.source.bundleID, size: 20)
                    }
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(width: NotchStyle.wing)
            }
            Spacer(minLength: 0)
            if model.showsWings {
                LevelMark().frame(width: NotchStyle.wing)
            }
        }
        .padding(.horizontal, NotchStyle.closedTop + (model.isHovering ? NotchStyle.hoverGrow : 0))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle() }
        .contextMenu { PanelMenuItems() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Notch DJ"))
        .accessibilityHint(Text("Opens the mixer"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Three still bars. The closed notch never animates.
private struct LevelMark: View {
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach([7.0, 12.0, 9.0], id: \.self) { height in
                Capsule().fill(Color.white.opacity(0.75)).frame(width: 2.5, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Settings, Onboarding and Quit, for right-clicks on the notch and the top bar.
struct PanelMenuItems: View {
    @EnvironmentObject private var model: DJModel

    var body: some View {
        Button("Settings…") { model.showSettings() }
        Button("Show Onboarding…") { model.showOnboarding() }
        Divider()
        Button("Quit Notch DJ") { NSApp.terminate(nil) }
    }
}

private struct ExpandedPanel: View {
    @EnvironmentObject private var model: DJModel
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var hero

    var body: some View {
        VStack(spacing: 0) {
            PanelTopBar()
                .frame(height: metrics.header)
            VStack(spacing: 10) {
                PermissionBanner()
                tabContent
            }
            .padding(.horizontal, metrics.padding + NotchStyle.openTop)
            .padding(.top, metrics.padding * 0.7)
            .padding(.bottom, metrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(tokens.panel)
        .foregroundStyle(tokens.text)
        .environment(\.metersLive, mixer.liveMeters && mixer.capture == .authorized)
        .environment(\.heroNamespace, reduceMotion ? nil : hero)
    }

    private var tabContent: some View {
        ZStack {
            switch model.tab {
            case .home: HomeView().transition(slide)
            case .mixer: MixerView().transition(slide)
            case .dj: DJTab().transition(slide)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var slide: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let direction = model.tabDirection
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: 12 * direction)),
                           removal: .opacity.combined(with: .offset(x: -12 * direction)))
    }
}

/// The DJ tab in the chosen template's layout.
private struct DJTab: View {
    @EnvironmentObject private var prefs: DJPreferences

    var body: some View {
        prefs.template.template.makeDJView()
    }
}
