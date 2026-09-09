//
//  TileStore.swift
//  MVK++ Phone App
//

import Foundation
import os

/// Persistent tile storage, on two shelves.
///
/// `cache` is what the map fills in as the rider moves: disposable, trimmed to
/// a budget, and safe to lose. `offline` is what the rider deliberately
/// downloaded in Settings: never trimmed, never evicted, and checked first.
///
/// Both live in the App Group container rather than `Caches/`, because iOS
/// purges `Caches/` under disk pressure — an offline map that vanishes the
/// first time storage runs low is not an offline map.
///
/// Tiles are filed under a *source* id, not a base-map id: "Utcatérkép",
/// "Sötét" and "Halvány" are the same OpenStreetMap bytes under different
/// colour treatments, so one download covers all three.
final class TileStore: @unchecked Sendable {

    static let shared = TileStore()

    enum Shelf: String {
        case cache
        case offline
    }

    /// Runtime cache ceiling. Roughly 20k filtered tiles — far more than a
    /// city's worth of casual panning, and small enough that nobody notices
    /// it in Settings › Storage.
    static let cacheBudgetBytes: Int64 = 400 * 1024 * 1024

    private let root: URL
    private let fileManager = FileManager.default
    /// Serialises directory creation. Tile *files* are independent, so reads
    /// and writes of distinct tiles need no coordination at all.
    private let directoryQueue = DispatchQueue(label: "hu.futozs.mvk.tilestore.dirs")
    private var knownDirectories: Set<String> = []

    private init() {
        let container = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: FavoritesStore.appGroupID)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = container.appendingPathComponent("MapTiles", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        excludeFromBackup(root)
    }

    // MARK: - Paths

    private func directory(shelf: Shelf, source: String, _ tile: TileCoordinate) -> URL {
        root
            .appendingPathComponent(shelf.rawValue, isDirectory: true)
            .appendingPathComponent(source, isDirectory: true)
            .appendingPathComponent(String(tile.z), isDirectory: true)
            .appendingPathComponent(String(tile.x), isDirectory: true)
    }

    private func file(shelf: Shelf, source: String, _ tile: TileCoordinate) -> URL {
        directory(shelf: shelf, source: source, tile).appendingPathComponent("\(tile.y).tile")
    }

    func shelfRoot(_ shelf: Shelf, source: String? = nil) -> URL {
        let base = root.appendingPathComponent(shelf.rawValue, isDirectory: true)
        guard let source else { return base }
        return base.appendingPathComponent(source, isDirectory: true)
    }

    // MARK: - Reading

    /// The offline pack wins: it is the copy the rider paid data for, and it
    /// is the only one guaranteed to be there on a dead connection.
    func read(source: String, _ tile: TileCoordinate) -> (data: Data, shelf: Shelf)? {
        if let data = try? Data(contentsOf: file(shelf: .offline, source: source, tile), options: .mappedIfSafe) {
            return (data, .offline)
        }
        if let data = try? Data(contentsOf: file(shelf: .cache, source: source, tile), options: .mappedIfSafe) {
            return (data, .cache)
        }
        return nil
    }

    func contains(shelf: Shelf, source: String, _ tile: TileCoordinate) -> Bool {
        fileManager.fileExists(atPath: file(shelf: shelf, source: source, tile).path)
    }

    // MARK: - Writing

    func write(_ data: Data, shelf: Shelf, source: String, _ tile: TileCoordinate) {
        let directory = directory(shelf: shelf, source: source, tile)
        ensureDirectory(directory)
        try? data.write(to: file(shelf: shelf, source: source, tile), options: .atomic)
    }

    private func ensureDirectory(_ url: URL) {
        // One `createDirectory` syscall per tile would double the write cost;
        // the paths repeat heavily (256 tiles share a z/x folder), so a
        // memo of what already exists pays for itself immediately.
        let key = url.path
        let needsCreate = directoryQueue.sync { knownDirectories.insert(key).inserted }
        guard needsCreate else { return }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - Accounting

    /// Bytes on disk for one shelf, optionally narrowed to a single source.
    /// Walks the tree, so callers keep it off the main thread.
    func byteSize(shelf: Shelf, source: String? = nil) -> Int64 {
        let base = shelfRoot(shelf, source: source)
        guard let walker = fileManager.enumerator(
            at: base,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    func tileCount(shelf: Shelf, source: String) -> Int {
        let base = shelfRoot(shelf, source: source)
        guard let walker = fileManager.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let url as URL in walker where url.pathExtension == "tile" {
            count += 1
        }
        return count
    }

    // MARK: - Removal

    func removeAll(shelf: Shelf, source: String? = nil) {
        try? fileManager.removeItem(at: shelfRoot(shelf, source: source))
        directoryQueue.sync { knownDirectories.removeAll() }
    }

    /// Drops the oldest half of the runtime cache when it outgrows its budget.
    /// Halving rather than trimming to the line keeps this from running on
    /// every launch once the cache is warm.
    func trimCacheIfNeeded() {
        let base = shelfRoot(.cache)
        guard byteSize(shelf: .cache) > Self.cacheBudgetBytes else { return }

        guard let walker = fileManager.enumerator(
            at: base,
            includingPropertiesForKeys: [.contentAccessDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var files: [(url: URL, accessed: Date)] = []
        for case let url as URL in walker where url.pathExtension == "tile" {
            let values = try? url.resourceValues(forKeys: [.contentAccessDateKey])
            files.append((url, values?.contentAccessDate ?? .distantPast))
        }

        files.sort { $0.accessed < $1.accessed }
        for entry in files.prefix(files.count / 2) {
            try? fileManager.removeItem(at: entry.url)
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
