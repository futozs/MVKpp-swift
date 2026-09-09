//
//  MapTileOverlay.swift
//  MVK++ Phone App
//

import Foundation
import MapKit

/// The raster base map, with the whole tile pipeline behind it.
///
/// A tile is looked for in memory, then in the offline pack, then in the
/// runtime disk cache, and only then on the network. Colour treatment
/// ("Sötét", "Halvány") is applied once and the *result* is what gets stored,
/// so panning back over ground already seen costs a file read and nothing
/// else — no download, no Core Image, no re-encode.
///
/// That layering is the fix for the old behaviour: every tile used to be
/// re-fetched and re-filtered whenever it fell out of a 400-entry memory
/// cache, which during a pinch meant forty simultaneous downloads plus forty
/// PNG encodes, and a map that went blank while it caught up.
final class MapTileOverlay: MKTileOverlay {

    // MARK: - Shared infrastructure

    /// One session for every overlay ever created. The previous code built a
    /// session (and a 256 MB `URLCache`) per overlay instance, and created a
    /// fresh instance on every base-map switch.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // We keep our own disk cache of the *processed* tile, so URLCache
        // would only duplicate storage for the raw bytes.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Raised from 6 to keep pace with the offline downloader's own
        // concurrency (see `OfflineMapManager.parallelism`) — a lower cap
        // here just queued the extra requests instead of running them.
        configuration.httpMaximumConnectionsPerHost = 12
        configuration.timeoutIntervalForRequest = 12
        configuration.waitsForConnectivity = false
        // OSM's tile usage policy requires an identifying User-Agent; a
        // generic one gets throttled or blocked outright.
        configuration.httpAdditionalHeaders = ["User-Agent": TileNetwork.userAgent]
        return URLSession(configuration: configuration)
    }()

    /// Decoded-tile bytes, budgeted in bytes rather than entries — a count
    /// limit says nothing about memory pressure, which is what actually
    /// evicts.
    private static let memory: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    /// Blown-up stand-ins, kept apart from the real tiles so they can never be
    /// mistaken for one — and on a small budget, because they are worth
    /// exactly one zoom gesture each.
    private static let placeholders: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    /// Core Image is GPU-bound; letting forty tiles into it at once just
    /// queues them behind each other while starving the render loop.
    private static let processingQueue = DispatchQueue(
        label: "hu.futozs.mvk.tiles.process",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private static let processingGate = DispatchSemaphore(
        value: max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
    )
    private static let ioQueue = DispatchQueue(
        label: "hu.futozs.mvk.tiles.io",
        qos: .userInitiated,
        attributes: .concurrent
    )

    // MARK: - Instance

    let option: TileLayerOption

    /// Called with the tile's map rect whenever a tile is answered
    /// asynchronously — that is, from anywhere but the memory cache.
    ///
    /// `MKTileOverlayRenderer` draws a tile's slot once, when it asks for it.
    /// A tile handed back after that pass is simply never painted: MapKit does
    /// not come back for it. That is the whole "vibrálás" and the map that
    /// goes blank when you zoom in — the bytes had arrived, nothing had asked
    /// the renderer to use them. Whoever owns the renderer listens here and
    /// invalidates the rect.
    var onTileReady: ((MKMapRect) -> Void)?

    private let isLabels: Bool
    private let filter: TileFilter?
    /// Where raw bytes live — shared between every layer built on the same
    /// tile server, so one offline download serves all of them.
    private let sourceId: String
    /// Where the colour-treated result lives. Same as `sourceId` when there
    /// is no treatment to apply.
    private let outputId: String

    init(option: TileLayerOption, labels: Bool = false) {
        self.option = option
        isLabels = labels
        filter = labels ? nil : option.filter
        sourceId = (labels ? option.labelsSourceId : option.sourceId) ?? option.sourceId
        outputId = (labels || option.filter == nil) ? sourceId : "\(sourceId)~\(option.id)"

        super.init(urlTemplate: labels ? option.labelsUrl : option.url)

        canReplaceMapContent = !labels
        // Every source here serves 256-pixel tiles, and `tileSize` is what
        // MapKit multiplies by the screen scale to decide how much image it
        // expects behind a tile's slot. Left at the 256 default it asks a
        // 3× screen for 768 pixels, is handed 256, and quietly draws nothing —
        // that is the map turning into an empty grid the moment you pinch.
        // Declaring 512 points per tile makes the arithmetic come out on a
        // Retina screen, and MapKit asks for one zoom level coarser.
        tileSize = CGSize(width: Self.tilePoints, height: Self.tilePoints)
        // Past this level the source has no tiles; MapKit scales the last
        // real level up rather than requesting nothing and drawing a hole.
        maximumZ = option.maxNativeZoom
        minimumZ = 1
    }

    // MARK: - Tile loading

    /// Answers a tile, and never answers with nothing.
    ///
    /// This is the whole anti-flicker rule. A zoom step asks for a fresh level
    /// of tiles all at once, and `canReplaceMapContent` means there is no
    /// Apple base map underneath: a slot with no answer yet is not "loading",
    /// it is a black hole in the map. However fast the fetch is, answering it
    /// asynchronously still costs at least one frame of nothing, and a
    /// screenful of those on every pinch is the map appearing to strobe.
    ///
    /// So the answer is always immediate. In order of preference: the tile
    /// itself from memory, the tile itself off disk, or — failing both — the
    /// zoom level the rider is coming *from*, cropped and blown up to stand in
    /// for it. The stand-in is soft, but it is the same ground in the same
    /// place, so a zoom reads as the picture sharpening rather than as the
    /// picture disappearing and coming back. The real tile replaces it a
    /// moment later, once `onTileReady` has asked for a repaint.
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let tile = TileCoordinate(z: path.z, x: path.x, y: path.y)

        if let cached = Self.memory.object(forKey: memoryKey(tile)) {
            result(cached as Data, nil)
            return
        }

        // A memory-mapped read of a file we have already decided exists. Done
        // here rather than hopped onto a queue precisely because a hop is a
        // dropped frame, and MapKit calls this off the main thread anyway.
        if let ready = readProcessed(tile) {
            remember(ready, tile)
            result(ready, nil)
            return
        }

        // Nothing exact. Stand in with the level above and go and get the real
        // one; `answered` keeps the contract that `result` fires exactly once.
        var answered = false
        if let placeholder = placeholder(for: tile) {
            answered = true
            result(placeholder, nil)
        }

        let deliver: (Data?) -> Void = { [weak self] data in
            if !answered {
                answered = true
                result(data, nil)
            }
            guard let self, data != nil else { return }
            // Either the stand-in is on screen and has to be replaced, or the
            // renderer drew this slot empty before the answer arrived. Both
            // need the same thing: paint here again.
            self.onTileReady?(Self.mapRect(for: tile))
        }

        Self.ioQueue.async { [weak self] in
            // MapKit waits forever on a tile whose callback never fires, so
            // even the impossible path has to answer.
            guard let self else {
                deliver(nil)
                return
            }

            if let stored = TileStore.shared.read(source: self.sourceId, tile) {
                // The colour treatment is filed on the shelf its source came
                // from. A downloaded area therefore pays Core Image once, ever
                // — before, the treated copy went on the trimmable runtime
                // shelf, so an offline pack still meant re-filtering the same
                // tiles on every zoom, which is what made a downloaded map
                // flicker exactly like an un-downloaded one.
                self.process(raw: stored.data, tile: tile, into: stored.shelf, storeRaw: false) { processed in
                    deliver(processed ?? stored.data)
                }
                return
            }

            self.download(tile, result: deliver)
        }
    }

    /// The best stand-in for a tile that is not ready: an ancestor already in
    /// memory, cropped to this tile's footprint and scaled up.
    ///
    /// Memory only, and at most four levels up. Reaching further, or onto
    /// disk, would cost more than the frame it is trying to save — and four
    /// levels is already a sixteenth of a tile stretched over a whole one,
    /// which is as soft as a stand-in can usefully get.
    private func placeholder(for tile: TileCoordinate) -> Data? {
        if let ready = Self.placeholders.object(forKey: memoryKey(tile)) {
            return ready as Data
        }

        for step in 1...4 {
            let level = tile.z - step
            guard level >= minimumZ else { return nil }
            let ancestor = TileCoordinate(z: level, x: tile.x >> step, y: tile.y >> step)
            guard let source = Self.memory.object(forKey: memoryKey(ancestor)) as Data?,
                  let scaled = TileImageProcessor.upscale(source, ancestor: ancestor, target: tile)
            else { continue }

            Self.placeholders.setObject(scaled as NSData, forKey: memoryKey(tile), cost: scaled.count)
            return scaled
        }
        return nil
    }

    /// Fetches and caches a tile without drawing it — used to warm the cache
    /// one zoom level ahead of the rider, and by the offline downloader.
    /// The completion reports whether bytes ended up on disk.
    func warm(_ tile: TileCoordinate, shelf: TileStore.Shelf = .cache, completion: @escaping (Bool) -> Void) {
        guard tile.z <= maximumZ, tile.z >= minimumZ else {
            completion(false)
            return
        }
        // What matters is having the *drawable* form ready. Warming raw bytes
        // alone left the expensive half of the work — the colour treatment —
        // to happen mid-pinch, which defeated the point of prefetching.
        if TileStore.shared.contains(shelf: shelf, source: outputId, tile) {
            completion(true)
            return
        }

        // The raw tile may already be on disk from another layer built on the
        // same source; then only the treatment is missing.
        if let stored = TileStore.shared.read(source: sourceId, tile) {
            process(raw: stored.data, tile: tile, into: stored.shelf, storeRaw: false) { _ in
                completion(true)
            }
            return
        }

        fetch(tile) { [weak self] data in
            guard let self, let data else {
                completion(false)
                return
            }
            TileStore.shared.write(data, shelf: shelf, source: self.sourceId, tile)
            self.process(raw: data, tile: tile, into: shelf, storeRaw: false) { _ in
                completion(true)
            }
        }
    }

    // MARK: - Steps

    private func readProcessed(_ tile: TileCoordinate) -> Data? {
        guard outputId != sourceId else { return TileStore.shared.read(source: sourceId, tile)?.data }
        return TileStore.shared.read(source: outputId, tile)?.data
    }

    private func download(_ tile: TileCoordinate, result: @escaping (Data?) -> Void) {
        fetch(tile) { [weak self] data in
            guard let self else {
                result(nil)
                return
            }
            guard let data else {
                // Nothing on the network and nothing on disk: rather than
                // hand MapKit a hole, blow up whatever ancestor tile we do
                // have. Blurry is a state a rider can read; white is not.
                result(self.ancestorFallback(for: tile))
                return
            }
            self.process(raw: data, tile: tile, into: .cache, storeRaw: true) { processed in
                result(processed ?? data)
            }
        }
    }

    private func fetch(_ tile: TileCoordinate, completion: @escaping (Data?) -> Void) {
        let path = MKTileOverlayPath(x: tile.x, y: tile.y, z: tile.z, contentScaleFactor: 1)
        Self.session.dataTask(with: url(forTilePath: path)) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, !data.isEmpty, (200..<300).contains(status) else {
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }

    /// Applies the colour treatment (if any), files the results, and hands
    /// back what should be drawn.
    /// Applies the colour treatment (if any), files the result on `shelf`,
    /// and hands back what should be drawn.
    private func process(
        raw: Data,
        tile: TileCoordinate,
        into shelf: TileStore.Shelf,
        storeRaw: Bool,
        completion: @escaping (Data?) -> Void
    ) {
        if storeRaw {
            TileStore.shared.write(raw, shelf: shelf, source: sourceId, tile)
        }

        guard let filter else {
            remember(raw, tile)
            completion(raw)
            return
        }

        Self.processingQueue.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            Self.processingGate.wait()
            let processed = TileImageProcessor.apply(filter, to: raw)
            Self.processingGate.signal()

            if let processed {
                TileStore.shared.write(processed, shelf: shelf, source: self.outputId, tile)
                self.remember(processed, tile)
            }
            completion(processed)
        }
    }

    /// Walks up to six zoom levels out looking for something already stored.
    ///
    /// The colour-treated copy is preferred, then the memory cache, then the
    /// raw source — an offline pack holds raw tiles, so on a dead connection
    /// that last option is usually the one that saves the frame.
    private func ancestorFallback(for tile: TileCoordinate) -> Data? {
        for step in 1...6 {
            guard tile.z - step >= minimumZ else { return nil }
            let ancestor = TileCoordinate(z: tile.z - step, x: tile.x >> step, y: tile.y >> step)

            var candidate = readProcessed(ancestor)
                ?? Self.memory.object(forKey: memoryKey(ancestor)) as Data?

            if candidate == nil, let raw = TileStore.shared.read(source: sourceId, ancestor)?.data {
                candidate = filter.flatMap { TileImageProcessor.apply($0, to: raw) } ?? raw
            }

            guard let candidate else { continue }
            if let scaled = TileImageProcessor.upscale(candidate, ancestor: ancestor, target: tile) {
                return scaled
            }
        }
        return nil
    }

    // MARK: - Geometry

    /// Points of ground one 256-pixel tile covers. See the note in `init`.
    private static let tilePoints: CGFloat = 512

    /// How far MapKit's requested zoom sits below the Leaflet-style zoom the
    /// rest of the app talks in — one level, because a tile is declared at
    /// twice its pixel size. The prefetcher has to warm the levels MapKit will
    /// actually ask for, not the ones on screen.
    static let zoomOffset = -Int(log2(Double(tilePoints) / 256))


    /// The slippy tile's footprint in MapKit's projection. Both schemes are
    /// Web Mercator over the same world square, so this is a straight divide.
    static func mapRect(for tile: TileCoordinate) -> MKMapRect {
        let side = MKMapSize.world.width / pow(2, Double(tile.z))
        return MKMapRect(
            x: Double(tile.x) * side,
            y: Double(tile.y) * side,
            width: side,
            height: side
        )
    }

    // MARK: - Memory cache

    private func memoryKey(_ tile: TileCoordinate) -> NSString {
        "\(outputId)/\(tile.z)/\(tile.x)/\(tile.y)" as NSString
    }

    private func remember(_ data: Data, _ tile: TileCoordinate) {
        let key = memoryKey(tile)
        Self.memory.setObject(data as NSData, forKey: key, cost: data.count)
        // The stand-in has been superseded; keeping it would only compete for
        // memory with the tile that replaced it.
        Self.placeholders.removeObject(forKey: key)
    }

    static func clearMemory() {
        memory.removeAllObjects()
        placeholders.removeAllObjects()
    }
}

enum TileNetwork {
    static let userAgent = "MVK++/2.0 (hu.futozs.mvk; iOS)"
}
