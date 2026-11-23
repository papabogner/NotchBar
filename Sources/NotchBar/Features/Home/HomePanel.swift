import SwiftUI

/// The master page: a glance at everything, in three columns. Each widget's title opens
/// its full tab.
struct HomePanel: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var media: MediaController
    @ObservedObject var usage: ClaudeUsageStore
    @ObservedObject var timer: TimerModel
    @ObservedObject var calendar: CalendarStore
    @ObservedObject var weather: WeatherStore
    @ObservedObject var volumes: AppVolumeMixer
    @ObservedObject var layout: HomeLayout
    @Environment(\.notchChrome) private var chrome
    @ObservedObject private var battery = BatteryMonitor.shared

    var body: some View {
        Group {
            if layout.isCustomizing {
                customize
            } else {
                cardGrid
            }
        }
        .frame(height: 210, alignment: .top)
    }

    /// Two columns that stay inside the panel: the song on the left, faders on the right.
    private var cardGrid: some View {
        VStack(alignment: .leading, spacing: chrome.density.spacing + 4) {
            HStack(alignment: .top, spacing: 18) {
                if layout.isEnabled(.nowPlaying), media.nowPlaying?.isPlaying == true {
                    nowPlayingColumn.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if layout.isEnabled(.mixer), vm.isEnabled(.mixer) {
                    mixerColumn.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxHeight: .infinity)
            if showsStatus {
                statusRow
            }
            if vm.ticker.isEnabled, let line = vm.ticker.current {
                Button {
                    vm.ticker.openCurrent()
                } label: {
                    Text(line.text).font(chrome.font(12, weight: line.breaking ? .semibold : .medium)).lineLimit(1)
                        .foregroundStyle(line.breaking ? chrome.accent : .white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PressableStyle(scale: 0.99))
            }
        }
    }

    private var showsStatus: Bool {
        !vm.agents.sessions.isEmpty || vm.mini.isEnabled || (vm.portfolio.isEnabled && vm.portfolio.pulse != nil)
            || battery.percent != nil || (layout.isEnabled(.weather) && weather.weather != nil)
            || soonEvent != nil
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            ForEach(vm.agents.sessions.prefix(2)) { session in
                HStack(spacing: 4) {
                    Circle().fill(session.state == .working ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(session.tool).lineLimit(1)
                }
            }
            if vm.mini.isEnabled {
                HStack(spacing: 4) {
                    Circle().fill(vm.mini.report.online ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text("mini").lineLimit(1)
                }
            }
            if vm.portfolio.isEnabled, let pulse = vm.portfolio.pulse {
                Text(pulse.totalText).lineLimit(1)
                Text(pulse.changeText).lineLimit(1).foregroundStyle(pulse.isUp ? Color.green : Color.red)
            }
            if let percent = battery.percent {
                Text("\(percent)%").foregroundStyle(percent <= 20 && !battery.charging ? Color.red : .white.opacity(0.7))
            }
            if layout.isEnabled(.weather), weather.access == .on, let report = weather.weather {
                Text("\(report.temperature)°").lineLimit(1)
            }
            if layout.isEnabled(.upNext), let event = soonEvent {
                Text(event.title).lineLimit(1).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .font(chrome.font(11, weight: .medium))
        .foregroundStyle(.white.opacity(0.82))
    }

    private var nowPlayingColumn: some View {
        let accent = Color(nsColor: media.accent)
        let entry = media.nowPlaying
        let playing = entry?.isPlaying == true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ArtworkView(image: media.artwork, size: 72, radius: 14, accent: accent, isAppIcon: media.artworkIsAppIcon)
                    .shadow(color: playing ? accent.opacity(0.55) : .clear, radius: playing ? 14 : 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry?.title ?? "Not Playing")
                        .font(chrome.font(15, weight: .semibold)).lineLimit(2)
                    Text(entry?.artist ?? " ")
                        .font(chrome.font(12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { vm.select(.media) }
            HStack(spacing: 22) {
                if entry?.source.canSkip != false {
                    TransportButton(symbol: "backward.fill", size: 13, diameter: 28) { media.previous() }
                }
                TransportButton(symbol: entry?.isPlaying == true ? "pause.fill" : "play.fill", size: 16, big: true, diameter: 34) {
                    media.togglePlayPause()
                }
                if entry?.source.canSkip != false {
                    TransportButton(symbol: "forward.fill", size: 13, diameter: 28) { media.next() }
                }
            }
            .frame(maxWidth: .infinity)
            if vm.spotify.isEnabled, entry?.source.bundleID == SpotifyConnect.spotifyBundle {
                SpotifyDeviceMenu(spotify: vm.spotify)
            }
        }
    }

    private var mixerColumn: some View {
        let entry = media.nowPlaying
        let strips = volumes.homeStrips(nowPlayingBundle: entry?.source.bundleID,
                                         nowPlayingName: entry?.source.appName,
                                         isPlaying: entry?.isPlaying == true)
        let extra = max(0, volumes.rows.filter(\.playing).count - strips.count)
        return VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if layout.isEnabled(.weather) { weatherChip }
                if layout.isEnabled(.upNext), let event = soonEvent { soonChip(event) }
                Button { vm.select(.mixer) } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                .help(extra > 0 ? "More apps" : "Mixer")
            }
            HStack(alignment: .top, spacing: 6) {
                slot {
                    MasterStrip(mixer: volumes, compact: true, detailed: false)
                }
                ForEach(strips) { row in
                    slot {
                        ChannelStrip(row: row, mixer: volumes, compact: true,
                                     highlighted: row.id == entry?.source.bundleID, detailed: false, spotify: vm.spotify)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func slot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity)
    }

    /// One line for Claude usage, a running agent, or a timer. Hidden when none of those matter.
    private var statusLine: String? {
        var parts: [String] = []
        if layout.isEnabled(.agents), let session = vm.agents.sessions.first {
            parts.append("\(session.tool) \(session.state.label)")
        }
        if layout.isEnabled(.claude), usage.sessionFraction > 0.005 {
            parts.append("Claude \(Int((usage.sessionFraction * 100).rounded()))%")
        }
        if layout.isEnabled(.timer), timer.isActive {
            parts.append("Timer")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "  ·  ")
    }

    private var soonEvent: CalendarEvent? {
        guard calendar.access == .granted else { return nil }
        let horizon = Date().addingTimeInterval(90 * 60)
        return calendar.upcoming.first { event in
            !event.isAllDay && event.end > Date() && event.start < horizon
        }
    }

    private var weatherChip: some View {
        Group {
            if weather.access == .on, let report = weather.weather {
                HStack(spacing: 6) {
                    Image(systemName: report.symbol).symbolRenderingMode(.multicolor).font(.system(size: 14))
                    Text("\(report.temperature)°").font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            } else if weather.access == .off {
                Button("Weather") { weather.turnOn() }
                    .buttonStyle(PressableStyle(scale: 0.96))
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private func soonChip(_ event: CalendarEvent) -> some View {
        Button { vm.select(.calendar) } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private var customize: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Customize Home").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { layout.isCustomizing = false }
                    .buttonStyle(PressableStyle(scale: 0.96))
                    .font(.system(size: 12, weight: .semibold))
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(layout.items) { item in
                        HStack(spacing: 8) {
                            Button { layout.setEnabled(item.card, !item.enabled) } label: {
                                Image(systemName: item.enabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.enabled ? .white : .white.opacity(0.35))
                            }
                            .buttonStyle(PressableStyle())
                            Text(item.card.title).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button { layout.move(item.card, up: true) } label: {
                                Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(PressableStyle())
                            Button { layout.move(item.card, up: false) } label: {
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(PressableStyle())
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

/// An icon and title that open the widget's full tab.
struct WidgetHeader<Icon: View>: View {
    let title: String
    var action: (() -> Void)?
    @ViewBuilder var icon: Icon
    @State private var hover = false

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 6) {
                icon.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Text(title).font(.system(size: 13, weight: .semibold))
                if action != nil {
                    Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white.opacity(hover ? 0.6 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct WidgetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.black)
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }
}

// MARK: - Widgets

struct HomeMediaWidget: View {
    @ObservedObject var media: MediaController
    let open: () -> Void

    var body: some View {
        let accent = Color(nsColor: media.accent)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                ArtworkView(image: media.artwork, size: 46, radius: 11, accent: accent, isAppIcon: media.artworkIsAppIcon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.nowPlaying?.title ?? "Nothing Playing").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text(media.nowPlaying?.artist ?? "Music, Spotify, VLC or a browser")
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let entry = media.nowPlaying { AudioWaves(isPlaying: entry.isPlaying, color: accent, height: 15) }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)

            if let entry = media.nowPlaying, entry.source.usesMediaKeys, !media.hasAccessibility {
                AccessibilityHint(app: entry.source.appName) { media.requestAccessibility() }
                    .frame(maxWidth: .infinity, minHeight: 38)
            } else {
            HStack(spacing: 28) {
                if media.nowPlaying?.source.canSkip != false {
                    TransportButton(symbol: "backward.fill", size: 14, diameter: 30) { media.previous() }
                }
                TransportButton(symbol: media.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill", size: 18, big: true, diameter: 38) {
                    media.togglePlayPause()
                }
                if media.nowPlaying?.source.canSkip != false {
                    TransportButton(symbol: "forward.fill", size: 14, diameter: 30) { media.next() }
                }
            }
            .frame(maxWidth: .infinity)
            }
        }
    }
}

struct HomeWeatherWidget: View {
    @ObservedObject var weather: WeatherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Weather") { Image(systemName: "cloud.sun") }
            switch weather.access {
            case .on:
                if let w = weather.weather {
                    HStack(spacing: 8) {
                        Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 22))
                        Text("\(w.temperature)°").font(.system(size: 28, weight: .semibold, design: .rounded))
                    }
                    Text(w.condition).font(.system(size: 13, weight: .semibold))
                    Text([w.place, "H \(w.high)° L \(w.low)°"].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                } else {
                    Text("Getting the weather…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
            case .off:
                Text("Uses your approximate location.").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                WidgetButton(title: "Show Weather") { weather.turnOn() }
            case .waiting:
                Text("Waiting for location access…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    WidgetButton(title: "Ask Again") { weather.turnOn() }
                    Button("Cancel") { weather.turnOff() }
                        .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
            case .denied:
                Text("Location access is off for NotchBar.").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                WidgetButton(title: "Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                }
            }
        }
    }
}

struct HomeClaudeWidget: View {
    @ObservedObject var usage: ClaudeUsageStore
    let open: () -> Void

    var body: some View {
        let fraction = usage.sessionFraction
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Claude", action: open) { ClaudeLogo(size: 13) }
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 5)
                    Circle().trim(from: 0, to: max(0.002, fraction))
                        .stroke(usageColor(fraction), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((fraction * 100).rounded()))%").font(.system(size: 11.5, weight: .semibold, design: .rounded))
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusText).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(usage.activity == .idle ? .white : (usage.activity == .waiting ? Color.claudeWaiting : .claude))
                    TimelineView(.everyMinute) { context in
                        Text(formatCountdown(to: usage.sessionResetsAt, now: context.date).map { "\($0) left" } ?? "No session")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            if let week = usage.weeklyWindows.first {
                Text("\(week.label) \(Int(week.percent.rounded()))%").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else {
                Text("\(formatTokens(usage.snapshot.weekTokens)) this week").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var statusText: String {
        switch usage.activity {
        case .working: return "Working"
        case .waiting: return "Needs you"
        case .idle: return usage.sessionIsReal ? "Session" : "Est. session"
        }
    }
}

struct HomeTimerWidget: View {
    @ObservedObject var timer: TimerModel
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Timer", action: open) { Image(systemName: "timer") }
            if timer.isActive || timer.phase == .finished {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 8) {
                        TimerRing(timer: timer, now: context.date, size: 22, lineWidth: 3, showsText: false)
                        Text(formatClock(timer.remaining(at: context.date)))
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(timer.isRunning ? Color.timerOrange : .white)
                    }
                }
                HStack(spacing: 8) {
                    if timer.phase == .finished {
                        RoundAction(symbol: "stop.fill", fill: Color.timerOrange, tint: .black, size: 30, help: "Stop") { timer.dismissAlert() }
                    } else {
                        RoundAction(symbol: timer.isRunning ? "pause.fill" : "play.fill", fill: Color.timerOrange.opacity(0.22),
                                    tint: .timerOrange, size: 30, help: timer.isRunning ? "Pause" : "Resume") {
                            timer.isRunning ? timer.pause() : timer.resume()
                        }
                        RoundAction(symbol: "xmark", fill: .white.opacity(0.14), tint: .white, size: 30, help: "Cancel") { timer.cancel() }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach([5, 15, 25], id: \.self) { minutes in
                        Button { timer.start(minutes: minutes) } label: {
                            Text("\(minutes)m").font(.system(size: 11.5, weight: .semibold))
                                .frame(width: 38, height: 26)
                                .background(Capsule().fill(.white.opacity(0.09)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle(scale: 0.92))
                    }
                }
            }
        }
    }
}
