//
//  TileLayerCatalog.swift
//  MVK++ Phone App
//

import Foundation

/// One selectable base map, ported from the web app's `TILE_LAYERS`.
///
/// Three of the five are the same OpenStreetMap tiles under different color
/// treatments — the web app applies a CSS `filter` to the tile layer, and
/// `TileImageProcessor` reproduces that chain in Core Image so the base maps
/// look identical on both clients.
struct TileLayerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String
    let url: String
    /// Where the raw bytes come from, before any colour treatment. Several
    /// layers share one source, so an offline download of "Utcatérkép" also
    /// covers "Sötét" and "Halvány".
    let sourceId: String
    /// Drawn above the base tiles — only satellite imagery needs place labels.
    let labelsUrl: String?
    let labelsSourceId: String?
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
            sourceId: "osm",
            labelsUrl: nil,
            labelsSourceId: nil,
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
            sourceId: "osm",
            labelsUrl: nil,
            labelsSourceId: nil,
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
            sourceId: "osm",
            labelsUrl: nil,
            labelsSourceId: nil,
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
            sourceId: "esri",
            labelsUrl: "https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}",
            labelsSourceId: "esri-labels",
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
            sourceId: "topo",
            labelsUrl: nil,
            labelsSourceId: nil,
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

    /// Every base map that a download of `sourceId` makes available offline.
    static func layers(source sourceId: String) -> [TileLayerOption] {
        all.filter { $0.sourceId == sourceId }
    }

    /// The distinct downloadable sources, in catalog order — one row each in
    /// the offline-map settings.
    static var downloadableSources: [TileLayerOption] {
        var seen: Set<String> = []
        return all.filter { seen.insert($0.sourceId).inserted }
    }
}
