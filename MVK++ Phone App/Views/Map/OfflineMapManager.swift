//
//  OfflineMapManager.swift
//  MVK++ Phone App
//

import Combine
import Foundation
import MapKit

/// A downloadable area. Deliberately a short list of named places rather than
/// a draw-your-own-rectangle tool: this is a Miskolc app, and the useful
/// answer is "the city" or "the city and everything MVK reaches".
struct OfflineArea: Identifiable, Hashable {
    let id: String
    let name: String
    let box: TileBoundingBox

    static let all: [OfflineArea] = [
        OfflineArea(
            id: "centre",
            name: "Belváros",
            box: TileBoundingBox(minLat: 48.085, minLon: 20.735, maxLat: 48.130, maxLon: 20.825)
        ),
        OfflineArea(
            id: "city",
            name: "Miskolc",
            box: TileBoundingBox(minLat: 48.030, minLon: 20.630, maxLat: 48.190, maxLon: 20.950)
        ),
        OfflineArea(
            id: "region",
            name: "Miskolc és környéke",
            box: TileBoundingBox(minLat: 47.960, minLon: 20.500, maxLat: 48.260, maxLon: 21.050)
        ),
    ]

    static func area(id: String?) -> OfflineArea {
        all.first { $0.id == id } ?? all[1]
    }
}

/// How deep the pyramid goes. Each extra level roughly quadruples the size,
/// so this is the single biggest lever the rider has over the download.
enum OfflineDetail: String, Identifiable, CaseIterable {
    case standard
    case detailed

    var id: String { rawValue }

    var zoomRange: ClosedRange<Int> {
        switch self {
        case .standard: return 10...16
        case .detailed: return 10...17
        }
    }

    var name: String {
        switch self {
        case .standard: return "Normál"
        case .detailed: return "Részletes"
        }
    }
}

/// What is currently on the device for one tile source.
struct OfflinePack: Codable, Hashable {
    var areaId: String
    var detail: String
    var tiles: Int
    var bytes: Int64
    var downloadedAt: Date
}

/// Downloads and tracks offline tile packs.
///
/// Tiles are filed under the *source*, not the base map, so downloading
/// "Utcatérkép" also makes "Sötét" and "Halvány" work offline — they are the
/// same OpenStreetMap bytes with a colour treatment applied on the device.
@MainActor
final class OfflineMapManager: ObservableObject {

    static let shared = OfflineMapManager()

    /// Rough per-tile figure from the Miskolc bbox: dense urban OSM PNGs run
    /// 15–25 KB, rural ones far less. Only ever shown as "kb.".
    static let estimatedBytesPerTile: Int64 = 18 * 1024

    struct Progress: Equatable {
        var sourceId: String
        var completed: Int
        var total: Int
        var failed: Int

        var fraction: Double {
            total > 0 ? Double(completed) / Double(total) : 0
        }
    }

    @Published private(set) var packs: [String: OfflinePack] = [:]
    @Published private(set) var progress: Progress?
    @Published var errorMessage: String?

    @Published var selectedAreaId: String {
        didSet { defaults.set(selectedAreaId, forKey: Self.areaKey) }
    }
    @Published var selectedDetail: OfflineDetail {
        didSet { defaults.set(selectedDetail.rawValue, forKey: Self.detailKey) }
    }

    private static let packKeyPrefix = "mvk_offline_pack_"
    private static let areaKey = "mvk_offline_area"
    private static let detailKey = "mvk_offline_detail"

    private let defaults = UserDefaults(suiteName: FavoritesStore.appGroupID) ?? .standard
    private var downloadTask: Task<Void, Never>?

    private init() {
        selectedAreaId = defaults.string(forKey: Self.areaKey) ?? OfflineArea.all[1].id
        selectedDetail = OfflineDetail(rawValue: defaults.string(forKey: Self.detailKey) ?? "") ?? .standard
        loadPackMetadata()
    }

    var isDownloading: Bool { progress != nil }

    var selectedArea: OfflineArea { OfflineArea.area(id: selectedAreaId) }

    /// How many tiles the current area/detail choice comes to, for one source.
    func estimatedTileCount() -> Int {
        TileMath.tileCount(in: selectedArea.box, zoomRange: selectedDetail.zoomRange)
    }

    func estimatedBytes() -> Int64 {
        Int64(estimatedTileCount()) * Self.estimatedBytesPerTile
    }

    func pack(for sourceId: String) -> OfflinePack? { packs[sourceId] }

    // MARK: - Download

    func download(_ option: TileLayerOption) {
        guard downloadTask == nil else { return }
        errorMessage = nil

        let area = selectedArea
        let detail = selectedDetail
        // The satellite layer is unreadable without its place-name overlay,
        // so both sources go down together or the download is pointless.
        let overlays = [MapTileOverlay(option: option)]
            + (option.labelsUrl != nil ? [MapTileOverlay(option: option, labels: true)] : [])

        let planned = overlays.reduce(0) { total, overlay in
            total + TileMath.tiles(
                in: area.box,
                zoomRange: detail.zoomRange.clamped(to: 1...overlay.maximumZ)
            ).count
        }

        progress = Progress(sourceId: option.sourceId, completed: 0, total: planned, failed: 0)

        downloadTask = Task { [weak self] in
            guard let self else { return }
            var completed = 0
            var failed = 0

            for overlay in overlays {
                let tiles = TileMath.tiles(
                    in: area.box,
                    zoomRange: detail.zoomRange.clamped(to: 1...overlay.maximumZ)
                )
                let outcome = await Self.run(overlay: overlay, tiles: tiles) { done, missed in
                    Task { @MainActor in
                        self.progress?.completed = completed + done
                        self.progress?.failed = failed + missed
                    }
                }
                completed += outcome.done
                failed += outcome.failed
                if Task.isCancelled { break }
            }

            let cancelled = Task.isCancelled
            let bytes = await Self.measure(sourceId: option.sourceId)

            self.progress = nil
            self.downloadTask = nil

            guard !cancelled else { return }

            if completed == 0 {
                self.errorMessage = "A letöltés nem sikerült — ellenőrizd a hálózatot."
                return
            }
            if failed > 0 {
                self.errorMessage = "\(failed) csempe nem jött le; a többi elérhető offline."
            }
            self.store(
                OfflinePack(
                    areaId: area.id,
                    detail: detail.rawValue,
                    tiles: completed,
                    bytes: bytes,
                    downloadedAt: Date()
                ),
                for: option.sourceId
            )
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progress = nil
    }

    func delete(_ option: TileLayerOption) {
        TileStore.shared.removeAll(shelf: .offline, source: option.sourceId)
        if let labels = option.labelsSourceId {
            TileStore.shared.removeAll(shelf: .offline, source: labels)
        }
        MapTileOverlay.clearMemory()
        packs.removeValue(forKey: option.sourceId)
        defaults.removeObject(forKey: Self.packKeyPrefix + option.sourceId)
    }

    // MARK: - Worker

    /// Raised from 4: on a modern connection four in flight left most of the
    /// download waiting on round-trip latency instead of bandwidth. Matched
    /// by `MapTileOverlay`'s `httpMaximumConnectionsPerHost` so this actually
    /// gets that many concurrent requests instead of queuing behind the
    /// session's own connection cap.
    private static let parallelism = 12

    private static func run(
        overlay: MapTileOverlay,
        tiles: [TileCoordinate],
        onProgress: @escaping (Int, Int) -> Void
    ) async -> (done: Int, failed: Int) {
        var done = 0
        var failed = 0
        var index = 0

        await withTaskGroup(of: Bool.self) { group in
            func addNext() {
                guard index < tiles.count else { return }
                let tile = tiles[index]
                index += 1
                group.addTask {
                    await withCheckedContinuation { continuation in
                        overlay.warm(tile, shelf: .offline) { continuation.resume(returning: $0) }
                    }
                }
            }

            for _ in 0..<min(parallelism, tiles.count) { addNext() }

            while let succeeded = await group.next() {
                if succeeded { done += 1 } else { failed += 1 }
                // Reporting every tile would push thousands of hops onto the
                // main actor; a progress bar cannot show more than this.
                if (done + failed) % 25 == 0 { onProgress(done, failed) }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                addNext()
            }
        }

        onProgress(done, failed)
        return (done, failed)
    }

    private static func measure(sourceId: String) async -> Int64 {
        await Task.detached(priority: .utility) {
            TileStore.shared.byteSize(shelf: .offline, source: sourceId)
        }.value
    }

    // MARK: - Metadata

    private func loadPackMetadata() {
        for option in TileLayerCatalog.downloadableSources {
            let key = Self.packKeyPrefix + option.sourceId
            guard let raw = defaults.data(forKey: key),
                  let pack = try? JSONDecoder().decode(OfflinePack.self, from: raw)
            else { continue }
            packs[option.sourceId] = pack
        }
    }

    private func store(_ pack: OfflinePack, for sourceId: String) {
        packs[sourceId] = pack
        guard let encoded = try? JSONEncoder().encode(pack) else { return }
        defaults.set(encoded, forKey: Self.packKeyPrefix + sourceId)
    }
}
