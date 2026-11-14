//
//  NewsModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// MVK's announcements as the worker prepares them (`core/news.ts`).
struct NewsRun: Decodable, Hashable {
    let text: String
    var bold: Bool?
    var italic: Bool?
    /// Only http(s), mailto and tel links survive.
    var href: String?
    /// The GTFS route_id of a recognised route mention.
    var route: String?
}

struct NewsListItem: Decodable, Hashable {
    let lead: [NewsRun]?
    let runs: [NewsRun]
}

enum NewsBlock: Decodable, Hashable {
    case paragraph([NewsRun])
    case heading([NewsRun])
    case label([NewsRun])
    case list([NewsListItem])

    private enum CodingKeys: String, CodingKey { case kind, runs, items }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "h": self = .heading(try container.decode([NewsRun].self, forKey: .runs))
        case "label": self = .label(try container.decode([NewsRun].self, forKey: .runs))
        case "list": self = .list(try container.decode([NewsListItem].self, forKey: .items))
        default: self = .paragraph(try container.decode([NewsRun].self, forKey: .runs))
        }
    }

    var kind: String {
        switch self {
        case .paragraph: return "p"
        case .heading: return "h"
        case .label: return "label"
        case .list: return "list"
        }
    }
}

struct NewsItem: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    /// MVK's category; null instead of the generic "Egyéb".
    let type: String?
    let modifiedAt: Double
    let validFrom: Double?
    let validUntil: Double?
    let summary: String
    /// Route ids mentioned, in order of first mention.
    let routes: [String]
    let blocks: [NewsBlock]
}

struct NewsRoute: Decodable, Hashable {
    let short: String
    let color: String
    let text: String
}

struct NewsFeed: Decodable {
    let fetchedAt: Double
    /// MVK is not answering; the last good list is shown.
    let stale: Bool
    let items: [NewsItem]
    let routes: [String: NewsRoute]
}

/// The news list with its seen-state (web `useNews`): refreshed every
/// 10 minutes, re-asked on open when older than 2.
@MainActor
final class NewsModel: ObservableObject {
    @Published private(set) var feed: NewsFeed?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = true

    /// The seen IDs — synced, so a read item is read on every device.
    private static let seenKey = "mvk_news_seen"
    private static let seenMax = 80
    private var loadedAt = Date.distantPast
    private var timer: Task<Void, Never>?

    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                try? await Task.sleep(for: .seconds(10 * 60))
            }
        }
    }

    deinit { timer?.cancel() }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let url = try APIClient.shared.url(path: "/engine/news")
            let (data, response) = try await APIClient.shared.session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw NewsError.message(status == 503 ? "Az MVK hírei most nem érhetők el." : "Nem sikerült betölteni (\(status)).")
            }
            feed = try JSONDecoder().decode(NewsFeed.self, from: data)
            error = nil
            loadedAt = Date()
        } catch NewsError.message(let message) {
            error = message
        } catch {
            self.error = "Nem sikerült betölteni."
        }
    }

    private enum NewsError: Error { case message(String) }

    private var seen: Set<Int> { Set(LocalStore.shared.json(Self.seenKey, as: [Int].self) ?? []) }

    var unseenCount: Int {
        let seen = seen
        return (feed?.items ?? []).filter { !seen.contains($0.id) }.count
    }

    /// On opening the list: what is new now is returned, and all of it is
    /// marked seen.
    func markAllSeen() -> Set<Int> {
        let seenNow = seen
        let fresh = Set((feed?.items ?? []).map(\.id).filter { !seenNow.contains($0) })
        if !fresh.isEmpty, let feed {
            var list = LocalStore.shared.json(Self.seenKey, as: [Int].self) ?? []
            for id in feed.items.map(\.id) where !list.contains(id) { list.append(id) }
            LocalStore.shared.setJSON(Self.seenKey, Array(list.suffix(Self.seenMax)))
        }
        return fresh
    }

    func refreshIfOld() {
        guard Date().timeIntervalSince(loadedAt) > 2 * 60 else { return }
        Task { await load() }
    }
}

/// News dates in Budapest time, in Hungarian.
enum NewsTime {
    private static let zone = TimeZone(identifier: "Europe/Budapest") ?? .current

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }

    /// The list's calendar tab: "30" / "okt".
    static func dateTab(_ unix: Double) -> (day: String, month: String) {
        let date = Date(timeIntervalSince1970: unix)
        let month = formatter("LLL").string(from: date).replacingOccurrences(of: ".", with: "")
        return (formatter("d").string(from: date), month)
    }

    /// "ma 13:34", "tegnap 10:01", "október 28. 09:57"; another year with the
    /// year and no time.
    static func published(_ unix: Double, now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: unix)
        let ymd = formatter("yyyy-MM-dd")
        let day = ymd.string(from: date)
        let time = formatter("HH:mm").string(from: date)
        if day == ymd.string(from: now) { return "ma \(time)" }
        if day == ymd.string(from: now.addingTimeInterval(-86_400)) { return "tegnap \(time)" }
        if day.prefix(4) != ymd.string(from: now).prefix(4) { return formatter("yyyy. MMMM d.").string(from: date) }
        return "\(formatter("MMMM d.").string(from: date)) \(time)"
    }

    /// The short form of a bare address for the link text: "mvkzrt.hu/…".
    static func prettyURL(_ href: String) -> String {
        guard let url = URL(string: href), let host = url.host() else { return href }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return url.path().count > 1 || url.query() != nil ? "\(bare)/…" : bare
    }
}
