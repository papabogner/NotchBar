import AppKit

/// Rotating lines beside the closed notch. Off until the user turns it on.
@MainActor
final class TickerStore: ObservableObject {
    enum Source: String, CaseIterable, Identifiable, Codable {
        case nowPlaying, calendar, claude, agents, custom, feed, crypto
        var id: String { rawValue }
        var title: String {
            switch self {
            case .nowPlaying: return "Now Playing"
            case .calendar: return "Up Next"
            case .claude: return "Claude"
            case .agents: return "Agents"
            case .custom: return "Custom Text"
            case .feed: return "Feed"
            case .crypto: return "Crypto"
            }
        }
    }

    @Published var isEnabled: Bool { didSet { persist(); reschedule() } }
    @Published var sources: Set<Source> { didSet { persist(); reschedule() } }
    @Published var width: Double { didSet { persist() } }
    @Published var interval: Double {
        didSet {
            persist()
            rotation?.stop()
            rotation = nil
            reschedule()
        }
    }
    @Published var customText: String { didSet { persist() } }
    @Published var feedURL: String { didSet { persist(); reschedule() } }
    @Published private(set) var feedLines: [String] = []
    @Published private(set) var cryptoLine: String = ""
    /// Filled by the agent monitor when that feature is on. Empty until then.
    @Published var agentLine: String = ""
    @Published private(set) var menuBarHidden = false

    private let media: MediaController
    private let calendar: CalendarStore
    private let usage: ClaudeUsageStore
    private var rotation: EfficientTimer?
    private var cryptoTimer: EfficientTimer?
    private var feedTimer: EfficientTimer?
    private var index = 0
    private let spaceObserver = SpaceChangeObserver()
    private static let key = "tickerSettings"

    init(media: MediaController, calendar: CalendarStore, usage: ClaudeUsageStore) {
        self.media = media
        self.calendar = calendar
        self.usage = usage
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Stored.self, from: data) {
            isEnabled = saved.enabled
            sources = Set(saved.sources.compactMap(Source.init(rawValue:)))
            width = saved.width
            interval = saved.interval
            customText = saved.custom
            feedURL = saved.feed
        } else {
            isEnabled = false
            sources = [.nowPlaying]
            width = 180
            interval = 8
            customText = ""
            feedURL = ""
        }
        spaceObserver.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.refreshMenuBar() }
        }
        spaceObserver.start()
        refreshMenuBar()
        reschedule()
    }

    var shows: Bool { isEnabled && !menuBarHidden && current != nil }
    var current: String? {
        let lines = linesNow()
        guard !lines.isEmpty else { return nil }
        return lines[index % lines.count]
    }

    func toggle(_ source: Source) {
        if sources.contains(source) { sources.remove(source) } else { sources.insert(source) }
    }

    private func linesNow() -> [String] {
        var lines: [String] = []
        if sources.contains(.nowPlaying), let entry = media.nowPlaying, entry.isPlaying {
            lines.append("\(entry.title) · \(entry.artist)")
        }
        if sources.contains(.calendar), let event = calendar.upcoming.first {
            lines.append(event.title)
        }
        if sources.contains(.claude) {
            lines.append("Claude \(Int((usage.sessionFraction * 100).rounded()))%")
        }
        if sources.contains(.agents), !agentLine.isEmpty { lines.append(agentLine) }
        if sources.contains(.custom), !customText.isEmpty { lines.append(customText) }
        if sources.contains(.feed) { lines.append(contentsOf: feedLines.prefix(5)) }
        if sources.contains(.crypto), !cryptoLine.isEmpty { lines.append(cryptoLine) }
        return lines
    }

    private func reschedule() {
        if isEnabled {
            if rotation == nil {
                rotation = EfficientTimer(interval: max(3, interval), tolerance: 1) { [weak self] in
                    MainActor.assumeIsolated { self?.advance() }
                }
            }
            rotation?.start()
        } else {
            rotation?.stop()
        }
        if isEnabled && sources.contains(.crypto) {
            if cryptoTimer == nil {
                cryptoTimer = EfficientTimer(interval: 60, tolerance: 15) { [weak self] in
                    MainActor.assumeIsolated { self?.fetchCrypto() }
                }
            }
            cryptoTimer?.start()
            fetchCrypto()
        } else {
            cryptoTimer?.stop()
        }
        if isEnabled && sources.contains(.feed), let url = URL(string: feedURL), url.scheme?.hasPrefix("http") == true {
            if feedTimer == nil {
                feedTimer = EfficientTimer(interval: 15 * 60, tolerance: 60) { [weak self] in
                    MainActor.assumeIsolated { self?.fetchFeed() }
                }
            }
            feedTimer?.start()
            fetchFeed()
        } else {
            feedTimer?.stop()
        }
    }

    private func advance() {
        index += 1
        objectWillChange.send()
    }

    private func refreshMenuBar() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let hidden = abs(screen.frame.maxY - screen.visibleFrame.maxY) < 2
        if hidden != menuBarHidden { menuBarHidden = hidden }
    }

    private func fetchCrypto() {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,cardano&vs_currencies=eur") else { return }
        Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] else { return }
            let pairs = [("bitcoin", "BTC"), ("ethereum", "ETH"), ("solana", "SOL"), ("cardano", "ADA")]
            let text = pairs.compactMap { id, symbol -> String? in
                guard let price = json[id]?["eur"] else { return nil }
                return "\(symbol) €\(Int(price.rounded()))"
            }.joined(separator: "  ")
            guard let self, !text.isEmpty else { return }
            self.cryptoLine = text
        }
    }

    private func fetchFeed() {
        guard let url = URL(string: feedURL), url.scheme?.hasPrefix("http") == true else { return }
        Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            let lines = Self.parseFeed(data)
            guard let self, !lines.isEmpty else { return }
            self.feedLines = lines
        }
    }

    private static func parseFeed(_ data: Data) -> [String] {
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let list = json as? [String] { return list.filter { !$0.isEmpty } }
            if let object = json as? [String: Any] {
                if let titles = object["items"] as? [String] { return titles }
                if let items = object["items"] as? [[String: Any]] {
                    return items.compactMap { $0["title"] as? String }
                }
            }
        }
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var titles: [String] = []
        var rest = xml[...]
        while let start = rest.range(of: "<title>"), let end = rest.range(of: "</title>") , start.upperBound < end.lowerBound {
            let title = rest[start.upperBound..<end.lowerBound]
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { titles.append(title) }
            rest = rest[end.upperBound...]
        }
        return Array(titles.dropFirst().prefix(6))
    }

    private func persist() {
        let stored = Stored(enabled: isEnabled, sources: sources.map(\.rawValue), width: width, interval: interval,
                            custom: customText, feed: feedURL)
        UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: Self.key)
    }

    private struct Stored: Codable {
        var enabled: Bool
        var sources: [String]
        var width: Double
        var interval: Double
        var custom: String
        var feed: String
    }
}

/// Selector observer so the workspace notification does not capture the store in a sendable block.
private final class SpaceChangeObserver: NSObject {
    var onChange: (() -> Void)?

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(changed),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    @objc private func changed() {
        MainActor.assumeIsolated { onChange?() }
    }
}
