//
//  Route.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// A GTFS route.
///
/// The gateway ships routes in two shapes: `/gtfs/routes.json` sends
/// tuple-arrays (`[id, short, long, type, color, text]`) to keep the payload
/// small, while `/gtfs/timetable` embeds a keyed object. Decoding both here
/// keeps one `Route` type across the app instead of two near-identical ones.
struct Route: Decodable, Identifiable, Hashable {
    let id: String
    let short: String
    let long: String
    let type: String
    /// Bare hex, no leading "#" — normalized on decode.
    let color: String
    let text: String
    /// v3 (`?modes=`): mode, statistics key, operator.
    var mode: TransitMode?
    var key: String?
    var operatorName: String?

    /// GTFS route_type 900 is the tram family; everything MVK runs otherwise
    /// is a bus.
    var isTram: Bool { type == "900" }

    private enum CodingKeys: String, CodingKey {
        case id, short, long, type, color, text, mode, key
        case operatorName = "operator"
    }

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            id = try array.decode(String.self)
            short = try array.decode(String.self)
            long = try array.decode(String.self)
            type = try array.decode(String.self)
            color = Self.normalize(try array.decodeIfPresent(String.self), fallback: "888888")
            text = Self.normalize(try array.decodeIfPresent(String.self), fallback: "FFFFFF")
            if !array.isAtEnd { mode = ((try? array.decodeIfPresent(String.self)) ?? nil).flatMap(TransitMode.init(rawValue:)) }
            if !array.isAtEnd { key = (try? array.decodeIfPresent(String.self)) ?? nil }
            if !array.isAtEnd { operatorName = (try? array.decodeIfPresent(String.self)) ?? nil }
            return
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        id = try keyed.decode(String.self, forKey: .id)
        short = try keyed.decode(String.self, forKey: .short)
        long = try keyed.decode(String.self, forKey: .long)
        type = try keyed.decode(String.self, forKey: .type)
        color = Self.normalize(try keyed.decodeIfPresent(String.self, forKey: .color), fallback: "888888")
        text = Self.normalize(try keyed.decodeIfPresent(String.self, forKey: .text), fallback: "FFFFFF")
        mode = try? keyed.decodeIfPresent(TransitMode.self, forKey: .mode)
        key = try? keyed.decodeIfPresent(String.self, forKey: .key)
        operatorName = try? keyed.decodeIfPresent(String.self, forKey: .operatorName)
    }

    init(id: String, short: String, long: String, type: String, color: String, text: String) {
        self.id = id
        self.short = short
        self.long = long
        self.type = type
        self.color = Self.normalize(color, fallback: "888888")
        self.text = Self.normalize(text, fallback: "FFFFFF")
    }

    /// The feed is inconsistent about the leading "#" and sometimes omits the
    /// color entirely — same normalization the web client applies in `api.ts`.
    private static func normalize(_ raw: String?, fallback: String) -> String {
        guard let raw, !raw.isEmpty else { return fallback }
        let stripped = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        return stripped.isEmpty ? fallback : stripped
    }
}
