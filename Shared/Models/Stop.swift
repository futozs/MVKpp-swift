//
//  Stop.swift
//  MVK++ Watch App
//

import Foundation

/// A GTFS stop. `/gtfs/stops.json` returns tuple-shaped arrays
/// (`[id, code, name, lat, lon]`), not keyed objects, hence the custom decoding.
struct Stop: Decodable, Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let lat: Double
    let lon: Double
    /// v3 (`?modes=`): which feed — "mvk", "coach" (Volán) or "rail".
    var feed: String? = nil
    /// v3: the parent station a platform or bay belongs to.
    var parent: String? = nil
    /// v3: this is the station itself.
    var station = false
    /// v3: a Volán stop standing at the same place as this MVK pole; in the
    /// merged view it is not a separate item.
    var twinOf: String? = nil

    init(id: String, code: String, name: String, lat: Double, lon: Double) {
        self.id = id
        self.code = code
        self.name = name
        self.lat = lat
        self.lon = lon
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        code = try container.decode(String.self)
        name = try container.decode(String.self)
        lat = try container.decode(Double.self)
        lon = try container.decode(Double.self)
        if !container.isAtEnd { feed = Self.nonEmpty(try container.decodeIfPresent(String.self)) }
        if !container.isAtEnd { parent = Self.nonEmpty(try container.decodeIfPresent(String.self)) }
        if !container.isAtEnd { station = (try container.decodeIfPresent(Int.self) ?? 0) != 0 }
        if !container.isAtEnd { twinOf = Self.nonEmpty(try container.decodeIfPresent(String.self)) }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Matches by name, by the GTFS platform code (small 1-15 index), and by
    /// the rider-facing stop number embedded in `id` (e.g. "SP569" for "569")
    /// — `code` alone isn't what people mean by "stop code" in practice.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return false }
        let needle = query.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        return name.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains(needle)
            || code.lowercased().contains(needle)
            || id.lowercased().contains(needle)
    }
}
