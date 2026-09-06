//
//  TileLayerCatalog.swift
//  MVK++ Phone App
//

import CoreImage
import CoreImage.CIFilterBuiltins
import MapKit
import SwiftUI

/// One selectable base map, ported from the web app's `TILE_LAYERS`.
///
/// Three of the five are the same OpenStreetMap tiles under different color
/// treatments — the web app applies a CSS `filter` to the tile layer, and
/// `FilteredTileOverlay` reproduces that chain in Core Image so the base maps
/// look identical on both clients.
struct TileLayerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String
    let url: String
    /// Drawn above the base tiles — only satellite imagery needs place labels.
    let labelsUrl: String?
    let attribution: String
    let maxNativeZoom: Int
    /// Representative color, shown in the base map picker.
    let swatch: String
    let filter: TileFilter?
}

/// The CSS filter chain applied to a tile, expressed as its components.
struct TileFilter: Hashable {
    var invert = false
    /// Degrees.
    var hueRotate: Double = 0
    /// Multiplicative, like CSS `brightness()`.
    var brightness: Double = 1
    var contrast: Double = 1
    /// CSS `saturate()`.
    var saturate: Double = 1
    /// CSS `grayscale()`, 0…1.
    var grayscale: Double = 0

    static let dark = TileFilter(
        invert: true,
        hueRotate: 180,
        brightness: 0.86,
        contrast: 0.92,
        saturate: 0.65
    )

    static let faded = TileFilter(
        brightness: 1.06,
        contrast: 0.9,
        grayscale: 0.85
    )
}

enum TileLayerCatalog {

    private static let osmURL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    private static let osmAttribution = "© OpenStreetMap közreműködők"

    static let all: [TileLayerOption] = [
        TileLayerOption(
            id: "osm",
            name: "Utcatérkép",
            note: "OpenStreetMap",
            url: osmURL,
            labelsUrl: nil,
            attribution: osmAttribution,
            maxNativeZoom: 19,
            swatch: "E8E0D8",
            filter: nil
        ),
        TileLayerOption(
            id: "dark",
            name: "Sötét",
            note: "Sötétített OpenStreetMap",
            url: osmURL,
            labelsUrl: nil,
            attribution: osmAttribution,
            maxNativeZoom: 19,
            swatch: "20241F",
            filter: .dark
        ),
        TileLayerOption(
            id: "light",
            name: "Halvány",
            note: "Kifakított OpenStreetMap",
            url: osmURL,
            labelsUrl: nil,
            attribution: osmAttribution,
            maxNativeZoom: 19,
            swatch: "DEDEDC",
            filter: .faded
        ),
        TileLayerOption(
            id: "satellite",
            name: "Műhold",
            note: "Esri World Imagery",
            url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
            labelsUrl: "https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}",
            attribution: "© Esri, Maxar, Earthstar Geographics",
            maxNativeZoom: 19,
            swatch: "3F5B3C",
            filter: nil
        ),
        TileLayerOption(
            id: "topo",
            name: "Domborzat",
            note: "OpenTopoMap",
            url: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
            labelsUrl: nil,
            attribution: "Csempe: OpenTopoMap (CC-BY-SA), adat: © OpenStreetMap",
            maxNativeZoom: 17,
            swatch: "CBD3B0",
            filter: nil
        ),
    ]

    static let storageKey = "mvk_map_tile"

    static func layer(id: String?) -> TileLayerOption {
        all.first { $0.id == id } ?? all[0]
    }

    static var saved: TileLayerOption {
        layer(id: UserDefaults.standard.string(forKey: storageKey))
    }

    static func save(_ id: String) {
        UserDefaults.standard.set(id, forKey: storageKey)
    }
}

/// An `MKTileOverlay` that reproduces the web app's CSS tile filters.
///
/// Tiles are fetched, run through a Core Image chain, and re-encoded. The
/// filtered result is cached in memory, so panning back over ground already
/// seen costs nothing — without that, every pan would re-filter.
final class FilteredTileOverlay: MKTileOverlay {

    private let filter: TileFilter?
    private let maxNativeZoom: Int
    private let session: URLSession
    /// CSS filters operate on gamma-encoded sRGB values. Core Image linearises
    /// by default, which makes an inverted tile come out grey instead of dark —
    /// pinning the working colour space to sRGB is what makes the ported
    /// "Sötét" and "Halvány" layers match the web pixel for pixel.
    private let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])
    private let cache = NSCache<NSString, NSData>()

    init(option: TileLayerOption, labels: Bool = false) {
        filter = labels ? nil : option.filter
        maxNativeZoom = option.maxNativeZoom

        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        // OSM's tile usage policy requires an identifying User-Agent; a
        // generic one gets throttled or blocked outright.
        configuration.httpAdditionalHeaders = ["User-Agent": "MVK++/2.0 (hu.futozs.mvk; iOS)"]
        session = URLSession(configuration: configuration)

        super.init(urlTemplate: labels ? option.labelsUrl : option.url)

        canReplaceMapContent = !labels
        maximumZ = option.maxNativeZoom
        minimumZ = 1
        cache.countLimit = 400
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        guard filter != nil else {
            super.loadTile(at: path, result: result)
            return
        }

        let key = "\(path.z)/\(path.x)/\(path.y)/\(Int(path.contentScaleFactor))" as NSString
        if let cached = cache.object(forKey: key) {
            result(cached as Data, nil)
            return
        }

        let tileURL = url(forTilePath: path)
        session.dataTask(with: tileURL) { [weak self] data, _, error in
            guard let self else { return }
            guard let data, error == nil else {
                result(nil, error)
                return
            }
            guard let processed = self.apply(to: data) else {
                result(data, nil)
                return
            }
            self.cache.setObject(processed as NSData, forKey: key)
            result(processed, nil)
        }.resume()
    }

    /// CSS filter order is significant — invert, then hue, then the color
    /// controls — so the chain below mirrors the declaration exactly.
    private func apply(to data: Data) -> Data? {
        guard let filter, var image = CIImage(data: data) else { return nil }

        if filter.invert {
            let f = CIFilter.colorInvert()
            f.inputImage = image
            guard let out = f.outputImage else { return nil }
            image = out
        }

        if filter.hueRotate != 0 {
            let f = CIFilter.hueAdjust()
            f.inputImage = image
            f.angle = Float(filter.hueRotate * .pi / 180)
            guard let out = f.outputImage else { return nil }
            image = out
        }

        if filter.brightness != 1 {
            // CSS brightness multiplies the channels; Core Image's own
            // `brightness` is additive, so a color matrix does the job.
            let f = CIFilter.colorMatrix()
            f.inputImage = image
            let k = Float(filter.brightness)
            f.rVector = CIVector(x: CGFloat(k), y: 0, z: 0, w: 0)
            f.gVector = CIVector(x: 0, y: CGFloat(k), z: 0, w: 0)
            f.bVector = CIVector(x: 0, y: 0, z: CGFloat(k), w: 0)
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            guard let out = f.outputImage else { return nil }
            image = out
        }

        // `saturate` and `grayscale` are two ends of the same control: CSS
        // grayscale(g) equals a saturation of 1 − g.
        let saturation = filter.grayscale > 0 ? (1 - filter.grayscale) : filter.saturate
        if saturation != 1 || filter.contrast != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.saturation = Float(saturation)
            f.contrast = Float(filter.contrast)
            f.brightness = 0
            guard let out = f.outputImage else { return nil }
            image = out
        }

        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).pngData()
    }
}
