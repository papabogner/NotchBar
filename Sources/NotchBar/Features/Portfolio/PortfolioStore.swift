import AppKit
import Combine
import Foundation

/// A holdings total from a local JSON file and CoinGecko. Off until the menu turns it on.
@MainActor
final class PortfolioStore: ObservableObject {
    struct Pulse: Equatable {
        var totalText: String
        var changeText: String
        var top: String
        var isUp: Bool
        var line: String
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var pulse: Pulse?
    var onUpdate: (@MainActor () -> Void)?

    private var timer: EfficientTimer?
    private var watching = false
    private var lastFetch = Date.distantPast

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("NotchBar", isDirectory: true)
    }
    static var holdingsURL: URL { folder.appendingPathComponent("portfolio.json") }
    static var statusURL: URL { folder.appendingPathComponent("portfolio-status.json") }

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "portfolioEnabled")
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: "portfolioEnabled")
        if on { refresh(force: true) } else { pulse = nil; timer?.stop() }
        updateTimer()
        onUpdate?()
    }

    func setWatching(_ on: Bool) {
        watching = on
        updateTimer()
        if on && isEnabled { refresh(force: false) }
    }

    /// Creates the template if needed and opens it in the default editor.
    func editHoldings() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Self.holdingsURL.path) {
            try? Self.template.write(to: Self.holdingsURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(Self.holdingsURL)
    }

    func refresh(force: Bool) {
        guard isEnabled else { return }
        if !force, Date().timeIntervalSince(lastFetch) < 240, pulse != nil { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let override = Self.readOverride(), override.total != nil {
                self.pulse = Self.pulse(from: override)
                self.onUpdate?()
                return
            }
            let book = Self.readHoldings()
            let ids = book.holdings.map(\.id).filter { !$0.isEmpty }
            let prices = await Self.prices(ids: ids, currency: book.currency)
            self.lastFetch = Date()
            self.pulse = Self.pulse(book: book, prices: prices)
            self.onUpdate?()
        }
    }

    private func updateTimer() {
        guard isEnabled && watching else { timer?.stop(); return }
        if timer == nil {
            timer = EfficientTimer(interval: 5 * 60, tolerance: 60) { [weak self] in
                MainActor.assumeIsolated { self?.refresh(force: true) }
            }
        }
        timer?.start()
    }

    private struct Book {
        var currency = "EUR"
        var holdings: [(symbol: String, id: String, amount: Double)] = []
        var manual: [(name: String, value: Double)] = []
    }

    private struct Quote {
        var price: Double
        var changePct: Double
    }

    private struct Override {
        var total: Double?
        var changePct: Double?
        var note: String
    }

    private static func readHoldings() -> Book {
        guard let data = try? Data(contentsOf: holdingsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Book() }
        var book = Book()
        if let currency = root["currency"] as? String, !currency.isEmpty { book.currency = currency }
        if let list = root["holdings"] as? [[String: Any]] {
            book.holdings = list.compactMap { item in
                guard let symbol = item["symbol"] as? String, let id = item["coingecko"] as? String else { return nil }
                let amount = item["amount"] as? Double ?? (item["amount"] as? Int).map(Double.init) ?? 0
                return (symbol, id, amount)
            }
        }
        if let list = root["manual"] as? [[String: Any]] {
            book.manual = list.compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                let value = item["value"] as? Double ?? (item["value"] as? Int).map(Double.init) ?? 0
                return (name, value)
            }
        }
        return book
    }

    private static func readOverride() -> Override? {
        guard let data = try? Data(contentsOf: statusURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let total = root["total"] as? Double ?? (root["total"] as? Int).map(Double.init)
        let change = root["change24hPct"] as? Double ?? (root["change24hPct"] as? Int).map(Double.init)
        return Override(total: total, changePct: change, note: root["note"] as? String ?? "")
    }

    private static func prices(ids: [String], currency: String) async -> [String: Quote] {
        guard !ids.isEmpty else { return [:] }
        let vs = currency.lowercased()
        let joined = ids.joined(separator: ",")
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(joined)&vs_currencies=\(vs)&include_24hr_change=true"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var quotes: [String: Quote] = [:]
        for (id, value) in root {
            guard let fields = value as? [String: Any], let price = number(fields[vs]) else { continue }
            quotes[id] = Quote(price: price, changePct: number(fields["\(vs)_24h_change"]) ?? 0)
        }
        return quotes
    }

    private static func pulse(book: Book, prices: [String: Quote]) -> Pulse? {
        var crypto = 0.0
        var changeValue = 0.0
        var topSymbol = ""
        var topMove = 0.0
        for holding in book.holdings {
            guard let quote = prices[holding.id] else { continue }
            let value = holding.amount * quote.price
            crypto += value
            changeValue += value * quote.changePct / 100
            if abs(quote.changePct) > abs(topMove) {
                topMove = quote.changePct
                topSymbol = holding.symbol
            }
        }
        let manual = book.manual.reduce(0.0) { $0 + $1.value }
        let total = crypto + manual
        guard total > 0 || !book.holdings.isEmpty else { return nil }
        let previous = total - changeValue
        let pct = previous > 0 ? changeValue / previous * 100 : 0
        return make(total: total, pct: pct, change: changeValue, currency: book.currency, top: topSymbol, note: "")
    }

    private static func pulse(from override: Override) -> Pulse? {
        guard let total = override.total else { return nil }
        let pct = override.changePct ?? 0
        return make(total: total, pct: pct, change: total * pct / 100, currency: "EUR", top: "", note: override.note)
    }

    private static func make(total: Double, pct: Double, change: Double, currency: String, top: String, note: String) -> Pulse {
        let money = format(total, currency: currency)
        let delta = format(abs(change), currency: currency)
        let sign = pct >= 0 ? "+" : "−"
        let changeText = "\(sign)\(String(format: "%.1f", abs(pct)))% \(sign)\(delta)"
        let topText = note.isEmpty ? top : note
        let line = "Portfolio \(money) \(sign)\(String(format: "%.1f", abs(pct)))% \(topText)".trimmingCharacters(in: .whitespaces)
        return Pulse(totalText: money, changeText: changeText, top: topText, isUp: pct >= 0, line: line)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func format(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let digits = formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
        if currency.uppercased() == "EUR" { return "€\(digits)" }
        return "\(digits) \(currency.uppercased())"
    }

    /// Placeholder amounts only. Replace them in the file; NotchBar does not ship a real portfolio.
    private static let template = """
    {
      "currency": "EUR",
      "holdings": [
        {"symbol": "BTC", "coingecko": "bitcoin", "amount": 0.01},
        {"symbol": "ETH", "coingecko": "ethereum", "amount": 0.2},
        {"symbol": "SOL", "coingecko": "solana", "amount": 1},
        {"symbol": "ADA", "coingecko": "cardano", "amount": 100}
      ],
      "manual": [
        {"name": "Cash", "value": 100}
      ]
    }
    """
}
