import Foundation
import Security

/// RSS headlines and, when a bearer token is saved, recent posts from X. Off until those sources are on.
@MainActor
final class NewsTicker: ObservableObject {
    static let defaultFeeds = [
        "https://rss.orf.at/news.xml",
        "https://www.tagesschau.de/xml/rss2/",
        "https://feeds.reuters.com/reuters/worldNews",
        "https://hnrss.org/frontpage",
    ]
    static let defaultQuery = "(breaking OR eilmeldung) -is:retweet lang:de OR lang:en"

    var onNews: (@MainActor ([TickerLine]) -> Void)?
    var onPosts: (@MainActor ([TickerLine]) -> Void)?

    @Published var feeds: [String] {
        didSet { UserDefaults.standard.set(feeds, forKey: "tickerNewsFeeds") }
    }
    @Published var xQuery: String {
        didSet { UserDefaults.standard.set(xQuery, forKey: "tickerXQuery") }
    }
    @Published private(set) var hasToken = false

    private var timer: EfficientTimer?
    private var newsOn = false
    private var xOn = false
    private var backoffUntil = Date.distantPast

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "tickerNewsFeeds") ?? []
        feeds = saved.isEmpty ? Self.defaultFeeds : saved
        let query = UserDefaults.standard.string(forKey: "tickerXQuery") ?? ""
        xQuery = query.isEmpty ? Self.defaultQuery : query
        hasToken = XKeychain.load() != nil
    }

    func setToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { XKeychain.clear() } else { XKeychain.save(trimmed) }
        hasToken = !trimmed.isEmpty
        if xOn { refresh() }
    }

    func setActive(news: Bool, x: Bool) {
        let was = newsOn || xOn
        newsOn = news
        xOn = x && hasToken
        let now = newsOn || xOn
        if now && !was { refresh() }
        if now {
            if timer == nil {
                timer = EfficientTimer(interval: 5 * 60, tolerance: 60) { [weak self] in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
            timer?.start()
        } else {
            timer?.stop()
            if !news { onNews?([]) }
            if !xOn { onPosts?([]) }
        }
    }

    func refresh() {
        if newsOn { fetchFeeds() }
        if xOn, Date() >= backoffUntil { fetchPosts() }
    }

    private func fetchFeeds() {
        let list = feeds
        Task { @MainActor [weak self] in
            var lines: [TickerLine] = []
            var seen = Set<String>()
            for raw in list {
                guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true,
                      let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
                for item in FeedXML.parse(data) {
                    let key = item.link ?? item.title
                    guard seen.insert(key).inserted else { continue }
                    let breaking = item.date.map { Date().timeIntervalSince($0) < 30 * 60 } ?? false
                    let text = breaking ? "BREAKING  \(item.title)" : item.title
                    lines.append(TickerLine(id: "news-\(key)", text: text, url: item.link.flatMap(URL.init(string:)),
                                             priority: breaking ? 90 : 25, breaking: breaking))
                    if lines.count >= 12 { break }
                }
                if lines.count >= 12 { break }
            }
            self?.onNews?(Array(lines.prefix(8)))
        }
    }

    private func fetchPosts() {
        guard let token = XKeychain.load(), !token.isEmpty else { onPosts?([]); return }
        let query = xQuery.isEmpty ? Self.defaultQuery : xQuery
        Task { @MainActor [weak self] in
            guard let self else { return }
            var parts = URLComponents(string: "https://api.twitter.com/2/tweets/search/recent")
            parts?.queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "max_results", value: "10"),
                URLQueryItem(name: "tweet.fields", value: "created_at,public_metrics"),
                URLQueryItem(name: "expansions", value: "author_id"),
                URLQueryItem(name: "user.fields", value: "username"),
            ]
            guard let url = parts?.url else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 429 {
                self.backoffUntil = Date().addingTimeInterval(15 * 60)
                return
            }
            guard http.statusCode == 200 else { return }
            self.onPosts?(Self.parsePosts(data))
        }
    }

    private static func parsePosts(_ data: Data) -> [TickerLine] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tweets = root["data"] as? [[String: Any]] else { return [] }
        var names: [String: String] = [:]
        if let includes = root["includes"] as? [String: Any], let users = includes["users"] as? [[String: Any]] {
            for user in users {
                if let id = user["id"] as? String, let username = user["username"] as? String {
                    names[id] = username
                }
            }
        }
        return tweets.compactMap { tweet in
            guard let id = tweet["id"] as? String, let text = tweet["text"] as? String else { return nil }
            let metrics = tweet["public_metrics"] as? [String: Any]
            let likes = metrics?["like_count"] as? Int ?? 0
            let reposts = metrics?["retweet_count"] as? Int ?? 0
            guard likes + reposts >= 5 else { return nil }
            let author = names[tweet["author_id"] as? String ?? ""] ?? "x"
            let link = URL(string: "https://x.com/\(author)/status/\(id)")
            let trimmed = text.replacingOccurrences(of: "\n", with: " ")
            return TickerLine(id: "x-\(id)", text: "𝕏 @\(author): \(trimmed)", url: link, priority: 70, breaking: true)
        }
    }
}

enum XKeychain {
    private static let service = "com.local.notchbar.x"
    private static let account = "bearer"

    static func save(_ token: String) {
        clear()
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private final class FeedXML: NSObject, XMLParserDelegate {
    struct Item {
        var title: String
        var link: String?
        var date: Date?
    }

    private var items: [Item] = []
    private var current = ""
    private var title = ""
    private var link = ""
    private var date = ""
    private var inItem = false

    static func parse(_ data: Data) -> [Item] {
        let parser = FeedXML()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.items
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        current = ""
        if element == "item" || element == "entry" {
            inItem = true
            title = ""
            link = ""
            date = ""
        }
        if inItem, element == "link", link.isEmpty, let href = attributes["href"] { link = href }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { current += string }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            if element == "title" { title = text }
            if element == "link", link.isEmpty { link = text }
            if element == "pubDate" || element == "updated" || element == "published" { date = text }
            if element == "item" || element == "entry" {
                let parsed = FeedXML.date(from: date)
                if !title.isEmpty { items.append(Item(title: title, link: link.isEmpty ? nil : link, date: parsed)) }
                inItem = false
            }
        }
        current = ""
    }

    private static func date(from text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return rfc.date(from: text)
    }
}
