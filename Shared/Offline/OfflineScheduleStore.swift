//
//  OfflineScheduleStore.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// The downloaded timetable on disk.
///
/// Everything lives in the App Group container so the widget and the intents
/// extension read the same bytes the app wrote — a widget has a fraction of a
/// second to answer and no business making a network call, and on a phone with
/// no signal there is nothing to call anyway.
///
/// Two things are stored per service day. The gateway's own
/// `/gtfs/timetable` responses go down verbatim, so the timetable screen can
/// decode them with the types it already has; alongside them sits a per-stop
/// index built from those responses, which is what answers "mikor jön a
/// következő" without touching 114 files.
enum OfflineScheduleStore {

    // MARK: - Layout

    private static let rootName = "OfflineSchedule"
    private static let manifestName = "manifest.json"
    private static let indexName = "index.z"
    private static let routesName = "routes.z"
    private static let timetableFolder = "tt"

    private static var root: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: FavoritesStore.appGroupID)?
            .appendingPathComponent(rootName, isDirectory: true)
    }

    private static func dayFolder(_ ymd: String) -> URL? {
        root?.appendingPathComponent(ymd, isDirectory: true)
    }

    /// Route ids come from a third-party feed, so they are not trusted as path
    /// components. The hash keeps two sanitized-alike ids apart.
    private static func timetableFile(_ ymd: String, routeId: String, dir: String) -> URL? {
        let key = "\(routeId)|\(dir)"
        let safe = key.map { $0.isLetter || $0.isNumber ? $0 : "_" }.prefix(24)
        return dayFolder(ymd)?
            .appendingPathComponent(timetableFolder, isDirectory: true)
            .appendingPathComponent("\(safe)-\(djb2(key)).z")
    }

    private static func djb2(_ text: String) -> String {
        var hash: UInt32 = 5381
        for byte in text.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return String(hash, radix: 36)
    }

    // MARK: - Memory cache
    //
    // Decoding a weekday index is a few hundred kilobytes of JSON. A stop card
    // refreshes every four seconds, so the decode happens once and the result
    // is held; two days is enough to cover a query that straddles midnight.

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var days: [String: OfflineScheduleIndex] = [:]
        private var order: [String] = []
        private var manifest: OfflineScheduleManifest?

        func index(_ ymd: String, load: (String) -> OfflineScheduleIndex?) -> OfflineScheduleIndex? {
            lock.lock()
            if let hit = days[ymd] {
                lock.unlock()
                return hit
            }
            lock.unlock()

            guard let loaded = load(ymd) else { return nil }

            lock.lock()
            days[ymd] = loaded
            order.removeAll { $0 == ymd }
            order.append(ymd)
            while order.count > 2, let oldest = order.first {
                order.removeFirst()
                days.removeValue(forKey: oldest)
            }
            lock.unlock()
            return loaded
        }

        func cachedManifest(load: () -> OfflineScheduleManifest) -> OfflineScheduleManifest {
            lock.lock()
            if let manifest {
                lock.unlock()
                return manifest
            }
            lock.unlock()

            let loaded = load()
            lock.lock()
            manifest = loaded
            lock.unlock()
            return loaded
        }

        func invalidate() {
            lock.lock()
            days.removeAll()
            order.removeAll()
            manifest = nil
            lock.unlock()
        }
    }

    private static let cache = Cache()

    // MARK: - Manifest

    static var manifest: OfflineScheduleManifest {
        cache.cachedManifest {
            guard let url = root?.appendingPathComponent(manifestName),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(OfflineScheduleManifest.self, from: data)
            else { return .empty }
            return decoded
        }
    }

    static func writeManifest(_ manifest: OfflineScheduleManifest) {
        guard let root else { return }
        createFolder(root)
        guard let encoded = try? JSONEncoder().encode(manifest) else { return }
        try? encoded.write(to: root.appendingPathComponent(manifestName), options: .atomic)
        cache.invalidate()
    }

    /// A pack built from a superseded GTFS release is not shown: the release
    /// is exactly when times move.
    static func isUsable(feedVersion: String?) -> Bool {
        let stored = manifest
        guard !stored.isEmpty else { return false }
        guard let feedVersion, !feedVersion.isEmpty, !stored.feedVersion.isEmpty else { return true }
        return stored.feedVersion == feedVersion
    }

    static func hasSchedule(for ymd: String) -> Bool {
        manifest.covers(ymd)
    }

    // MARK: - Reading

    static func index(_ ymd: String) -> OfflineScheduleIndex? {
        cache.index(ymd) { day in
            guard let url = dayFolder(day)?.appendingPathComponent(indexName),
                  let data = readCompressed(url)
            else { return nil }
            return try? JSONDecoder().decode(OfflineScheduleIndex.self, from: data)
        }
    }

    static func timetable(routeId: String, dir: String, ymd: String) -> TimetableResponse? {
        guard let url = timetableFile(ymd, routeId: routeId, dir: dir),
              let data = readCompressed(url)
        else { return nil }
        return try? JSONDecoder().decode(TimetableResponse.self, from: data)
    }

    static func timetableRoutes(ymd: String) -> TimetableRoutesResponse? {
        guard let url = dayFolder(ymd)?.appendingPathComponent(routesName),
              let data = readCompressed(url)
        else { return nil }
        return try? JSONDecoder().decode(TimetableRoutesResponse.self, from: data)
    }

    // MARK: - Writing

    static func writeTimetable(_ data: Data, routeId: String, dir: String, ymd: String) {
        guard let url = timetableFile(ymd, routeId: routeId, dir: dir) else { return }
        createFolder(url.deletingLastPathComponent())
        writeCompressed(data, to: url)
    }

    static func writeTimetableRoutes(_ data: Data, ymd: String) {
        guard let folder = dayFolder(ymd) else { return }
        createFolder(folder)
        writeCompressed(data, to: folder.appendingPathComponent(routesName))
    }

    static func writeIndex(_ index: OfflineScheduleIndex, ymd: String) {
        guard let folder = dayFolder(ymd), let encoded = try? JSONEncoder().encode(index) else { return }
        createFolder(folder)
        writeCompressed(encoded, to: folder.appendingPathComponent(indexName))
        cache.invalidate()
    }

    // MARK: - Housekeeping

    static func removeAll() {
        guard let root else { return }
        try? FileManager.default.removeItem(at: root)
        cache.invalidate()
    }

    /// Drops days the manifest no longer lists — a shortened download must not
    /// leave last week's boards behind, pretending to be current.
    static func removeDays(notIn keep: Set<String>) {
        guard let root,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil
              )
        else { return }
        for entry in entries where entry.hasDirectoryPath && !keep.contains(entry.lastPathComponent) {
            try? FileManager.default.removeItem(at: entry)
        }
        cache.invalidate()
    }

    static func byteSize() -> Int64 {
        guard let root,
              let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey]
              )
        else { return 0 }

        var total: Int64 = 0
        for case let url as URL in walker {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - Compressed file IO

    private static func createFolder(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func writeCompressed(_ data: Data, to url: URL) {
        let payload = (try? (data as NSData).compressed(using: .zlib) as Data) ?? data
        try? payload.write(to: url, options: .atomic)
    }

    /// Falls back to the raw bytes so a file written before compression was
    /// available — or by a future build that drops it — still reads.
    private static func readCompressed(_ url: URL) -> Data? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        if let expanded = try? (raw as NSData).decompressed(using: .zlib) as Data { return expanded }
        return raw
    }
}
