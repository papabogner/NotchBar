import AppKit

/// Which cards Home shows, and in what order. Fewer cards is the default so the notch stays calm.
@MainActor
final class HomeLayout: ObservableObject {
    enum Card: String, CaseIterable, Identifiable, Codable {
        case nowPlaying, upNext, weather, claude, timer, activity, calendar, mixer, agents
        var id: String { rawValue }
        var title: String {
            switch self {
            case .nowPlaying: return "Now Playing"
            case .upNext: return "Up Next"
            case .weather: return "Weather"
            case .claude: return "Claude"
            case .timer: return "Timer"
            case .activity: return "Activity"
            case .calendar: return "Calendar"
            case .mixer: return "Mixer"
            case .agents: return "Agents"
            }
        }
        /// The cards a new install shows. The rest stay available in Customize Home.
        static let standard: [Card] = [.nowPlaying, .upNext, .weather, .claude]
    }

    struct Item: Identifiable, Equatable {
        var card: Card
        var enabled: Bool
        var id: String { card.id }
    }

    @Published private(set) var items: [Item] = []
    @Published var isCustomizing = false
    /// Snapshots turn this off so a preview doesn't rewrite the saved Home.
    var writesChanges = true

    private static let key = "homeCards"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Stored].self, from: data), !saved.isEmpty {
            var seen = Set<Card>()
            items = saved.compactMap { entry in
                guard let card = Card(rawValue: entry.id), seen.insert(card).inserted else { return nil }
                return Item(card: card, enabled: entry.enabled)
            }
            for card in Card.allCases where !seen.contains(card) {
                items.append(Item(card: card, enabled: false))
            }
        } else {
            items = Card.allCases.map { Item(card: $0, enabled: Card.standard.contains($0)) }
        }
    }

    var visible: [Card] { items.filter(\.enabled).map(\.card) }
    func isEnabled(_ card: Card) -> Bool { items.first { $0.card == card }?.enabled == true }

    func setEnabled(_ card: Card, _ on: Bool) {
        guard let index = items.firstIndex(where: { $0.card == card }) else { return }
        items[index].enabled = on
        persist()
    }

    func move(_ card: Card, up: Bool) {
        guard let index = items.firstIndex(where: { $0.card == card }) else { return }
        let next = up ? index - 1 : index + 1
        guard items.indices.contains(next) else { return }
        items.swapAt(index, next)
        persist()
    }

    private func persist() {
        guard writesChanges else { return }
        let stored = items.map { Stored(id: $0.card.rawValue, enabled: $0.enabled) }
        UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: Self.key)
    }

    private struct Stored: Codable {
        var id: String
        var enabled: Bool
    }
}
