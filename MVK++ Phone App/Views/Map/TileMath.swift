//
//  TileMath.swift
//  MVK++ Phone App
//

import CoreLocation
import Foundation

/// One slippy-map tile. The same (z, x, y) triple the tile servers, the disk
/// cache and the offline downloader all speak.
struct TileCoordinate: Hashable {
    let z: Int
    let x: Int
    let y: Int
}

/// A geographic rectangle. Offline packs are defined as one of these plus a
/// zoom range.
struct TileBoundingBox: Hashable {
    let minLat: Double
    let minLon: Double
    let maxLat: Double
    let maxLon: Double

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minLat && coordinate.latitude <= maxLat
            && coordinate.longitude >= minLon && coordinate.longitude <= maxLon
    }
}

/// Web-Mercator tile arithmetic (the OSM/Esri "slippy map" scheme).
enum TileMath {

    /// Mercator breaks down at the poles; every tile scheme clips here.
    private static let latitudeLimit = 85.05112878

    static func x(lon: Double, z: Int) -> Int {
        let n = pow(2.0, Double(z))
        return clamp(Int(floor((lon + 180) / 360 * n)), z: z)
    }

    static func y(lat: Double, z: Int) -> Int {
        let n = pow(2.0, Double(z))
        let radians = min(max(lat, -latitudeLimit), latitudeLimit) * .pi / 180
        let value = (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2 * n
        return clamp(Int(floor(value)), z: z)
    }

    private static func clamp(_ value: Int, z: Int) -> Int {
        let lastIndex = Int(pow(2.0, Double(z))) - 1
        return min(max(value, 0), lastIndex)
    }

    /// Every tile covering `box` at one zoom level, in row-major order —
    /// which is also roughly the order a rider pans through them.
    static func tiles(in box: TileBoundingBox, z: Int) -> [TileCoordinate] {
        let minX = x(lon: box.minLon, z: z)
        let maxX = x(lon: box.maxLon, z: z)
        // Tile rows run north to south, so the northern edge is the low index.
        let minY = y(lat: box.maxLat, z: z)
        let maxY = y(lat: box.minLat, z: z)

        var result: [TileCoordinate] = []
        result.reserveCapacity((maxX - minX + 1) * (maxY - minY + 1))
        for ty in minY...maxY {
            for tx in minX...maxX {
                result.append(TileCoordinate(z: z, x: tx, y: ty))
            }
        }
        return result
    }

    static func tiles(in box: TileBoundingBox, zoomRange: ClosedRange<Int>) -> [TileCoordinate] {
        zoomRange.flatMap { tiles(in: box, z: $0) }
    }

    /// Counted without materialising the list — the settings screen shows an
    /// estimate for every preset, and building a hundred thousand structs to
    /// print one number would be absurd.
    static func tileCount(in box: TileBoundingBox, zoomRange: ClosedRange<Int>) -> Int {
        zoomRange.reduce(0) { total, z in
            let width = x(lon: box.maxLon, z: z) - x(lon: box.minLon, z: z) + 1
            let height = y(lat: box.minLat, z: z) - y(lat: box.maxLat, z: z) + 1
            return total + width * height
        }
    }
}
