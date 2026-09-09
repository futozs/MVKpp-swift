//
//  SharedStopCache.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// A stop, flattened for storage. `Stop` itself decodes from the gateway's
/// tuple-shaped arrays and is deliberately not `Encodable`; this is the
/// keyed form that gets written to the App Group.
struct CachedStop: Codable, Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
    let lat: Double
    let lon: Double

    init(_ stop: Stop) {
        id = stop.id
        code = stop.code
        name = stop.name
        lat = stop.lat
        lon = stop.lon
    }

    /// Back to the catalog type the app works in. The mirror is what the
    /// phone reads on a cold launch with no signal, so the round trip has to
    /// close.
    var asStop: Stop {
        Stop(id: id, code: code, name: name, lat: lat, lon: lon)
    }

    /// The number printed on the stop sign — the only identifier riders
    /// actually carry. GTFS ids look like "SP569"; riders say "569".
    var riderCode: String {
        let digits = id.filter(\.isNumber)
        return digits.isEmpty ? code : digits
    }
}

/// The stop catalog, mirrored into the App Group container so extensions can
/// read it without a network round trip.
///
/// The widget needs this twice over: once to populate its stop picker (a
/// configuration query has a fraction of a second to answer, which is not
/// enough for a cold HTTP request), and once to show a stop's name while the
/// arrivals call is still in flight.
enum SharedStopCache {

    private static let fileName = "stops.json"
    private static let updatedKey = "mvk_stop_cache_updated"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: FavoritesStore.appGroupID)?
            .appendingPathComponent(fileName)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: FavoritesStore.appGroupID) ?? .standard
    }

    static var lastUpdated: Date? {
        let stamp = defaults.double(forKey: updatedKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    static func save(_ stops: [Stop]) {
        guard let fileURL, !stops.isEmpty else { return }
        let payload = stops.map(CachedStop.init)
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
        defaults.set(Date().timeIntervalSince1970, forKey: updatedKey)
    }

    static func load() -> [CachedStop] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CachedStop].self, from: data)
        else { return [] }
        return decoded
    }

    /// The whole mirror, as catalog stops — what `TransitStore` falls back to
    /// when `/gtfs/stops.json` cannot be reached.
    static func loadStops() -> [Stop] {
        load().map(\.asStop)
    }

    static func stop(id: String) -> CachedStop? {
        load().first { $0.id == id }
    }

    /// Name, code and free-text search in one pass — what a widget picker's
    /// search field needs.
    static func search(_ query: String, limit: Int = 40) -> [CachedStop] {
        let stops = load()
        let needle = query
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        guard !needle.isEmpty else { return Array(stops.prefix(limit)) }

        return stops.filter { stop in
            stop.name.folding(options: .diacriticInsensitive, locale: .current)
                .lowercased().contains(needle)
                || stop.riderCode.hasPrefix(needle)
                || stop.id.lowercased().contains(needle)
        }
        .prefix(limit)
        .map { $0 }
    }
}
