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
    /// v3 (`?modes=`): `mvk`, `coach` or `rail`.
    var feed: String?
    /// v3: the parent station a platform or bay belongs to.
    var parent: String?
    /// v3: the station itself.
    var station: Bool?
    /// v3: this Volán stop stands where this MVK stop does.
    var twinOf: String?

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
        if !container.isAtEnd { feed = (try? container.decodeIfPresent(String.self)) ?? nil }
        if !container.isAtEnd { parent = (try? container.decodeIfPresent(String.self)) ?? nil }
        if !container.isAtEnd {
            if (try? container.decodeNil()) == true {
                station = nil
            } else if let flag = try? container.decode(Int.self) {
                station = flag != 0
            } else {
                station = try? container.decode(Bool.self)
            }
        }
        if !container.isAtEnd { twinOf = (try? container.decodeIfPresent(String.self)) ?? nil }
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
