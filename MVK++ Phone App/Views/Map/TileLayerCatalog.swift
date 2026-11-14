//
//  TileLayerCatalog.swift
//  MVK++ Phone App
//

import Foundation
import MapKit

/// One selectable base map, backed by MapKit's own native rendering.
///
/// This used to be five raster tile sources fetched, colour-treated and
/// cached by hand — enough machinery (a disk cache, a placeholder pyramid, a
/// live zoom ceiling) to paper over the fact that a hand-rolled tile pipeline
/// can never quite match a first-party renderer for smoothness. Apple's own
/// map has no fetch-and-decode step to stutter on: the vector data is already
/// on the system, so panning and zooming are as smooth as Apple's own Maps
/// app. The trade a rider makes for that is losing the offline base-map pack
/// (`MKMapConfiguration` has no public bulk-download API) and the exact
/// colour-filtered look of the web app's OSM layers — `style` below picks the
/// closest native equivalent for each instead.
struct TileLayerOption: Identifiable, Hashable {

    /// What `TransitMapRepresentable` builds an `MKMapConfiguration` from.
    enum Style: Hashable {
        /// "Utcatérkép" — the everyday street map.
        case standard
        /// "Sötét" — same street map, forced to dark regardless of the
        /// system appearance, so the choice is the rider's and not iOS's.
        case standardDark
        /// "Halvány" — the muted emphasis style, forced light.
        case standardMuted
        /// "Műhold" — satellite imagery with roads and labels over it.
        case hybrid
        /// "Domborzat" — standard map with realistic elevation, the closest
        /// native stand-in for a hillshaded terrain layer.
        case standardTerrain
    }

    let id: String
    let name: String
    /// Short name for the small picker.
    let short: String
    let note: String
    let style: Style
    /// Representative color, shown in the base map picker.
    let swatch: String
}

enum TileLayerCatalog {

    static let all: [TileLayerOption] = [
        TileLayerOption(id: "osm", name: "Utcatérkép", short: "Utca", note: "Apple térkép", style: .standard, swatch: "E8E0D8"),
        TileLayerOption(id: "dark", name: "Sötét", short: "Sötét", note: "Sötétített Apple térkép", style: .standardDark, swatch: "20241F"),
        TileLayerOption(id: "light", name: "Halvány", short: "Halvány", note: "Kifakított Apple térkép", style: .standardMuted, swatch: "DEDEDC"),
        TileLayerOption(id: "satellite", name: "Műhold", short: "Műhold", note: "Apple műholdas térkép", style: .hybrid, swatch: "3F5B3C"),
        TileLayerOption(id: "topo", name: "Domborzat", short: "Terep", note: "Domborzati Apple térkép", style: .standardTerrain, swatch: "CBD3B0"),
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
