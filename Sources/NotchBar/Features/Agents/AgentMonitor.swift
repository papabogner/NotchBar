import AppKit

/// Claude Code and Codex sessions, from a status file, a running process, or a fresh transcript.
@MainActor
final class AgentMonitor: ObservableObject {
    struct Session: Identifiable, Equatable {
        enum State: String, Equatable { case working, waiting, done
            var label: String {
                switch self {
                case .working: return "working"
                case .waiting: return "needs you"
                case .done: return "done"
                }
            }
        }
        var id: String
        var tool: String
        var state: State
        var title: String
    }

    @Published private(set) var sessions: [Session] = []

    private let folder: URL
    private var watcher: FileWatcher?
    private var timer: EfficientTimer?
    private var active = false
    private var announced: [String: Session.State] = [:]
    private var primed = false
    var onAlert: ((String) -> Void)?
    var onLine: ((String) -> Void)?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        folder = support.appendingPathComponent("NotchBar/agents", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        timer = EfficientTimer(interval: 8, tolerance: 2) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var summary: String {
        guard let first = sessions.first else { return "" }
        return "\(first.tool) \(first.state.label)"
    }

    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        if on {
            if watcher == nil {
                watcher = FileWatcher(paths: [folder.path], latency: 0.4) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
                watcher?.start()
            }
            timer?.start()
            refresh()
        } else {
            timer?.stop()
            watcher = nil
        }
    }

    func refresh() {
        guard active else { return }
        let claude = Self.claudeProjects
        let codex = Self.codexSessions
        // The scan stays off the main actor. This task does not capture self; the hop back does.
        Task { @MainActor [weak self] in
            let snapshot = await Task.detached {
                (Self.runningTools(), Self.transcriptLabel(in: claude), Self.transcriptLabel(in: codex))
            }.value
            guard let self, self.active else { return }
            self.apply(tools: snapshot.0, claude: snapshot.1, codex: snapshot.2)
        }
    }

    private func apply(tools: Set<String>, claude: String?, codex: String?) {
        var found = readFiles()
        if tools.contains("claude"), !found.contains(where: { $0.tool == "Claude" }) {
            found.append(Session(id: "claude-process", tool: "Claude", state: Session.State(rawValue: claude ?? "") ?? .working, title: "Claude Code"))
        }
        if tools.contains("codex"), !found.contains(where: { $0.tool == "Codex" }) {
            found.append(Session(id: "codex-process", tool: "Codex", state: Session.State(rawValue: codex ?? "") ?? .working, title: "Codex"))
        }
        if found != sessions {
            noteChanges(new: found)
            sessions = found
            onLine?(summary)
        }
    }

    private func noteChanges(new: [Session]) {
        if !primed {
            primed = true
            for session in new { announced[session.id] = session.state }
            return
        }
        for session in new where session.state == .waiting || session.state == .done {
            if announced[session.id] != session.state {
                announced[session.id] = session.state
                NSSound(named: "Glass")?.play()
                onAlert?("\(session.tool) \(session.state.label)")
            }
        }
    }

    private func readFiles() -> [Session] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(FileStatus.self, from: data) else { return nil }
            let state = Session.State(rawValue: file.state) ?? .working
            return Session(id: file.id ?? url.lastPathComponent, tool: file.tool, state: state, title: file.title ?? file.tool)
        }
    }

    /// A transcript touched moments ago means the agent is mid-task. A quiet file means it finished.
    nonisolated private static func transcriptLabel(in directory: URL) -> String? {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let newest = urls.compactMap { url -> Date? in
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
        guard let newest else { return nil }
        if Date().timeIntervalSince(newest) < 20 { return "working" }
        if Date().timeIntervalSince(newest) < 120 { return "done" }
        return nil
    }

    nonisolated private static var claudeProjects: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    }

    nonisolated private static var codexSessions: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    }

    nonisolated private static func runningTools() -> Set<String> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return [] }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var tools = Set<String>()
        for line in text.split(separator: "\n") {
            let name = line.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
            if name == "claude" { tools.insert("claude") }
            if name == "codex" { tools.insert("codex") }
        }
        return tools
    }

    private struct FileStatus: Codable {
        var id: String?
        var tool: String
        var state: String
        var title: String?
    }
}
