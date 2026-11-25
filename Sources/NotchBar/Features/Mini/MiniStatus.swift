import Combine
import Foundation

/// The SSH result. A top-level type so a background task can return it.
struct MiniReport: Sendable, Equatable {
    var online = false
    var load = ""
    var disk = ""
    var uptime = ""
    var memory = ""
    var top = ""
    static let offline = MiniReport()
}

/// Status of another Mac, read over SSH. Off until the menu turns it on.
@MainActor
final class MiniStatus: ObservableObject {
    typealias Report = MiniReport

    @Published private(set) var isEnabled = false
    @Published var host: String
    @Published private(set) var report = Report.offline
    var onUpdate: (@MainActor () -> Void)?

    private var timer: EfficientTimer?
    private var watching = false

    var line: String {
        guard isEnabled else { return "" }
        guard report.online else { return "\(displayHost) offline" }
        var parts = [displayHost]
        if !report.load.isEmpty { parts.append("load \(report.load)") }
        if !report.disk.isEmpty { parts.append("\(report.disk) free") }
        if !report.uptime.isEmpty { parts.append(report.uptime) }
        return parts.joined(separator: " · ")
    }

    private var displayHost: String { host.isEmpty ? "mini" : host }

    init() {
        host = UserDefaults.standard.string(forKey: "miniHost") ?? "mini"
        isEnabled = UserDefaults.standard.bool(forKey: "miniStatusEnabled")
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: "miniStatusEnabled")
        if on { refresh() } else { report = .offline; timer?.stop() }
        updateTimer()
        onUpdate?()
    }

    func setHost(_ name: String) {
        host = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { host = "mini" }
        UserDefaults.standard.set(host, forKey: "miniHost")
        if isEnabled { refresh() }
    }

    /// Polls about once a minute, and only while Home or the ticker is showing this.
    func setWatching(_ on: Bool) {
        watching = on
        updateTimer()
        if on && isEnabled { refresh() }
    }

    func refresh() {
        guard isEnabled else { return }
        let target = displayHost
        Task { @MainActor [weak self] in
            let report = await Task.detached { MiniProbe.run(host: target) }.value
            guard let self else { return }
            self.report = report
            self.onUpdate?()
        }
    }

    private func updateTimer() {
        guard isEnabled && watching else { timer?.stop(); return }
        if timer == nil {
            timer = EfficientTimer(interval: 60, tolerance: 15) { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        timer?.start()
    }
}

enum MiniProbe {
    /// One remote shell. BatchMode means ssh never asks for a password.
    nonisolated static func run(host: String) -> MiniStatus.Report {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        task.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=4", host, script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return .offline }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard task.terminationStatus == 0, let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return .offline
        }
        return parse(text)
    }

    private nonisolated static let script = """
    uptime
    sysctl -n vm.loadavg
    df -h / | awk 'NR==2 {print $4}'
    memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ {print $2; exit}'
    ps -Ao pcpu,comm | sort -nr | awk 'NR==1 {print $1 "%", substr($0, index($0,$2))}'
    """

    private nonisolated static func parse(_ text: String) -> MiniStatus.Report {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        func at(_ index: Int) -> String { lines.indices.contains(index) ? lines[index] : "" }
        var uptime = ""
        let upLine = at(0)
        if let range = upLine.range(of: "up ") {
            uptime = String(upLine[range.upperBound...].prefix { $0 != "," }).trimmingCharacters(in: .whitespaces)
        }
        let load = at(1).split { $0 == " " || $0 == "{" || $0 == "}" }.first.map(String.init) ?? ""
        return MiniStatus.Report(online: true, load: load, disk: at(2), uptime: uptime, memory: at(3), top: at(4))
    }
}
