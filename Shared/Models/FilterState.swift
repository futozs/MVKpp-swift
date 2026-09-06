//
//  FilterState.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

enum VehicleTypeFilter: String, Codable, CaseIterable {
    case all, bus, tram

    var label: String {
        switch self {
        case .all: return "Mind"
        case .bus: return "Busz"
        case .tram: return "Villamos"
        }
    }
}

enum SpeedFilter: String, Codable, CaseIterable {
    case all, moving, idle

    var label: String {
        switch self {
        case .all: return "Mind"
        case .moving: return "Mozgó"
        case .idle: return "Álló"
        }
    }
}

enum VehicleSort: String, Codable, CaseIterable {
    case route, id, speed

    var label: String {
        switch self {
        case .route: return "Járat"
        case .id: return "Rendszám"
        case .speed: return "Sebesség"
        }
    }
}

/// Everything the map's control panel can change, persisted as one blob under
/// `mvk_filter_state` — the same key and shape the web app uses.
struct FilterState: Codable, Equatable {
    /// Free-text vehicle query (typed registration number).
    var vq: String = ""
    /// Pinned vehicle registrations, drawn highlighted and kept in frame.
    var watch: [String] = []
    var routes: [String] = []
    var type: VehicleTypeFilter = .all
    var speed: SpeedFilter = .all
    /// Radius in km around the rider, or nil for no distance limit.
    var nearMeKm: Double?
    var sort: VehicleSort = .route

    // Layers
    var stops: Bool = true
    var onlyWatched: Bool = false
    var shape: Bool = true
    var rstops: Bool = false
    /// Draw registration numbers next to the route tiles on the map.
    var labels: Bool = false
    /// Keep the map centred on the watched vehicle as it moves.
    var follow: Bool = false

    static let `default` = FilterState()

    /// At most this many vehicles can be pinned at once — beyond a dozen the
    /// map stops being readable.
    static let maxWatched = 12

    /// Whether anything deviates from the default view. Drives the "clear
    /// filters" affordance.
    var isActive: Bool {
        !vq.trimmingCharacters(in: .whitespaces).isEmpty
            || !watch.isEmpty
            || !routes.isEmpty
            || type != .all
            || speed != .all
            || nearMeKm != nil
            || onlyWatched
            || !stops
    }
}
