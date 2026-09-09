//
//  SharedCatalogCache.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// The rest of the static GTFS catalog — routes and the feed's own metadata —
/// mirrored into the App Group next to `SharedStopCache`.
///
/// The gateway's bytes are stored as they arrive rather than re-encoded.
/// `Route` decodes from two different shapes and is deliberately not
/// `Encodable`; keeping the payload verbatim means the offline read uses the
/// very same decoder as the online one, and there is no second format to keep
/// in step with the server.
enum SharedCatalogCache {

    private static let routesFile = "routes.json"
    private static let metaFile = "meta.json"

    private static func url(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: FavoritesStore.appGroupID)?
            .appendingPathComponent(name)
    }

    // MARK: - Routes

    static func saveRoutes(_ data: Data) {
        guard let url = url(routesFile), !data.isEmpty else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func routes() -> [Route] {
        guard let url = url(routesFile),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Route].self, from: data)
        else { return [] }
        return decoded
    }

    // MARK: - Feed metadata

    static func saveMeta(_ data: Data) {
        guard let url = url(metaFile), !data.isEmpty else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func meta() -> GtfsMeta? {
        guard let url = url(metaFile),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(GtfsMeta.self, from: data)
    }
}
