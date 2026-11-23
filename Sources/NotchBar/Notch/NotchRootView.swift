import SwiftUI

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var media: MediaController
    @ObservedObject var usage: ClaudeUsageStore
    @ObservedObject var timer: TimerModel

    var body: some View {
        VStack(spacing: 0) {
            notch
            Spacer(minLength: 0)
        }
        .frame(width: NotchController.canvas.width, height: NotchController.canvas.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var notch: some View {
        let size = vm.size
        return ZStack(alignment: .top) {
            if vm.isExpanded {
                ExpandedNotch(vm: vm, media: media, usage: usage, timer: timer)
                    .frame(width: vm.expandedSize.width, height: vm.expandedSize.height, alignment: .top)
                    .transition(.notchContent)
            } else {
                CollapsedNotch(vm: vm, media: media, usage: usage, timer: timer)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .transition(.notchContent)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(notchFill)
        .clipShape(NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius))
        .shadow(color: glow, radius: vm.isExpanded && theme.glow ? 22 : 16, y: 8)
        .environment(\.notchChrome, theme)
        .font(theme.font(13))
        .contentShape(NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius))
        .offset(x: vm.shapeOffset)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.leftWing)
    }

    private var theme: NotchAppearance.Theme {
        vm.appearance.displayed(album: media.artwork?.vibrantAverageColor)
    }

    /// Closed, and the band that meets the hardware, stay black. Glass is only the expanded body.
    @ViewBuilder private var notchFill: some View {
        if !vm.isExpanded {
            Color.black
        } else {
            VStack(spacing: 0) {
                Color.black.frame(height: vm.geometry.notchHeight)
                expandedBody
            }
        }
    }

    @ViewBuilder private var expandedBody: some View {
        switch theme.backgroundStyle {
        case .black:
            Color.black
        case .glass:
            NotchSystemGlass(tint: nil, intensity: theme.glassIntensity)
        case .tintedGlass:
            NotchSystemGlass(tint: theme.tint, intensity: theme.glassIntensity)
        case .gradient:
            LinearGradient(colors: [theme.background, theme.backgroundEnd], startPoint: angleStart, endPoint: angleEnd)
        }
    }

    private var glow: Color {
        if vm.isExpanded && theme.glow { return theme.accent.opacity(0.55 + theme.glassIntensity * 0.3) }
        return .black.opacity(vm.isExpanded || vm.banner != nil ? 0.45 : 0)
    }

    private var angleStart: UnitPoint {
        let radians = theme.angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private var angleEnd: UnitPoint {
        let radians = theme.angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }
}
