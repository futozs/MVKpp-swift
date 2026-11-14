//
//  News.swift
//  MVK++ (shared by the Phone and Watch targets)
//

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
