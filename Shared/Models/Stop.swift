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

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        code = try container.decode(String.self)
        name = try container.decode(String.self)
        lat = try container.decode(Double.self)
        lon = try container.decode(Double.self)
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
