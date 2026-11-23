import AppKit
import Foundation

/// Short German lines about this Mac. Runs only while the This Mac ticker source is on.
@MainActor
final class MacTicker: ObservableObject {
    var onItems: (@MainActor ([TickerLine]) -> Void)?

    private let mini: MiniStatus
    private let media: MediaController
    private let agentsFolder: URL
    private let tickerFolder: URL
    private let downloads: URL
    private var downloadsWatcher: FileWatcher?
    private var dropWatcher: FileWatcher?
    private var activateObserver: ActivateObserver?
    private var timer: EfficientTimer?
    private var active = false
    private var focus: [(name: String, start: Date, end: Date)] = []
    private var openName: String?
    private var openStart: Date?
    private var freshDownloads: [(name: String, date: Date)] = []

    init(mini: MiniStatus, media: MediaController) {
        self.mini = mini
        self.media = media
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let notch = support.appendingPathComponent("NotchBar", isDirectory: true)
        agentsFolder = notch.appendingPathComponent("agents", isDirectory: true)
        tickerFolder = notch.appendingPathComponent("ticker", isDirectory: true)
        downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: tickerFolder, withIntermediateDirectories: true)
    }

    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on { start() } else { stop() }
    }

    private func start() {
        let observer = ActivateObserver()
        observer.onActivate = { [weak self] app in self?.note(app) }
        observer.start()
        activateObserver = observer
        if let app = NSWorkspace.shared.frontmostApplication { note(app) }
        downloadsWatcher = FileWatcher(paths: [downloads.path], latency: 2) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        downloadsWatcher?.start()
        dropWatcher = FileWatcher(paths: [tickerFolder.path], latency: 0.5) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        dropWatcher?.start()
        timer = EfficientTimer(interval: 60, tolerance: 15) { [weak self] in
            MainActor.assumeIsolated { self?.publish() }
        }
        timer?.start()
        publish()
    }

    private func stop() {
        timer?.stop()
        timer = nil
        downloadsWatcher = nil
        dropWatcher = nil
        activateObserver = nil
        onItems?([])
    }

    private func note(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "App"
        let now = Date()
        if let openName, let openStart, openName != name {
            focus.append((openName, openStart, now))
        }
        if openName != name {
            openName = name
            openStart = now
        }
        let cutoff = now.addingTimeInterval(-2 * 60 * 60)
        focus.removeAll { $0.end < cutoff }
        publish()
    }

    private func publish() {
        guard active else { return }
        scanDownloads()
        var lines: [TickerLine] = []
        lines.append(contentsOf: agentLines())
        if let focusLine = focusLine() { lines.append(focusLine) }
        if let download = downloadLine() { lines.append(download) }
        if mini.isEnabled {
            if mini.report.online {
                let load = mini.report.load.isEmpty ? "" : ", CPU \(mini.report.load)"
                lines.append(TickerLine(id: "mini", text: "Mac mini: online\(load)", priority: 40))
            } else {
                lines.append(TickerLine(id: "mini", text: "Mac mini: offline", priority: 30))
            }
        }
        if let percent = BatteryMonitor.shared.percent, percent <= 20, !BatteryMonitor.shared.charging {
            lines.append(TickerLine(id: "battery", text: "Akku niedrig: \(percent)%", priority: 80))
        }
        if let entry = media.nowPlaying, entry.isPlaying {
            lines.append(TickerLine(id: "playing", text: "Läuft: \(entry.title) · \(entry.artist)", priority: 20))
        }
        lines.append(contentsOf: dropInLines())
        onItems?(lines)
    }

    private func agentLines() -> [TickerLine] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: agentsFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tool = root["tool"] as? String else { return nil }
            let state = root["state"] as? String ?? "working"
            let title = root["title"] as? String
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let minutes = max(1, Int(Date().timeIntervalSince(modified) / 60))
            let text: String
            let priority: Int
            switch state {
            case "done":
                text = "\(tool) fertig"
                priority = 55
            case "waiting":
                text = "\(tool) wartet"
                priority = 75
            default:
                let whereText = title.map { " in \($0)" } ?? ""
                text = "\(tool) arbeitet seit \(minutes) min\(whereText)"
                priority = 60
            }
            return TickerLine(id: "agent-\(url.lastPathComponent)", text: text, priority: priority)
        }
    }

    private func focusLine() -> TickerLine? {
        var totals: [String: TimeInterval] = [:]
        let now = Date()
        for segment in focus where segment.end > now.addingTimeInterval(-2 * 60 * 60) {
            totals[segment.name, default: 0] += segment.end.timeIntervalSince(segment.start)
        }
        if let openName, let openStart {
            totals[openName, default: 0] += now.timeIntervalSince(openStart)
        }
        guard let best = totals.max(by: { $0.value < $1.value }), best.value >= 60 else { return nil }
        let minutes = Int(best.value / 60)
        return TickerLine(id: "focus", text: "Fokus: \(minutes) min in \(best.key)", priority: 35)
    }

    private func scanDownloads() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let cutoff = Date().addingTimeInterval(-60 * 60)
        freshDownloads = urls.compactMap { url in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date > cutoff else { return nil }
            return (url.lastPathComponent, date)
        }.sorted { $0.date > $1.date }
    }

    private func downloadLine() -> TickerLine? {
        guard let newest = freshDownloads.first else { return nil }
        if freshDownloads.count == 1 {
            return TickerLine(id: "download", text: "Neu: \(newest.name)", priority: 45)
        }
        return TickerLine(id: "download", text: "\(freshDownloads.count) neue Downloads", priority: 45)
    }

    private func dropInLines() -> [TickerLine] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: tickerFolder, includingPropertiesForKeys: nil)) ?? []
        let now = Date()
        return urls.filter { $0.pathExtension == "json" }.flatMap { url -> [TickerLine] in
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = root["items"] as? [[String: Any]] else { return [] }
            return items.compactMap { item in
                guard let text = item["text"] as? String, !text.isEmpty else { return nil }
                if let expires = item["expires"] as? String, let date = ISO8601DateFormatter().date(from: expires), date < now {
                    return nil
                }
                let priority = item["priority"] as? Int ?? 50
                let link = (item["url"] as? String).flatMap(URL.init(string:))
                let source = item["source"] as? String ?? "ticker"
                return TickerLine(id: "drop-\(source)-\(text)", text: text, url: link, priority: priority)
            }
        }
    }
}

private final class ActivateObserver: NSObject {
    var onActivate: ((NSRunningApplication) -> Void)?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc private func activated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        MainActor.assumeIsolated { onActivate?(app) }
    }
}
