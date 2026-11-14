//
//  FilterState.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

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

/// The map's delay filter: by the official (MÁV+) delay, or our matcher's.
enum DelayFilter: String, Codable, CaseIterable {
    case all, late, ontime
}

/// Everything the map's controls can change, persisted as one blob under
/// `mvk_filter_state` — the same key and shape the web app uses.
struct FilterState: Codable, Equatable {
    var vq: String = ""
    var watch: [String] = []
    var routes: [String] = []
    /// Modes shown on the map ([] = every enabled mode).
    var modes: [TransitMode] = []
    /// Volán operating units; [] = all.
    var operators: [String] = []
    /// Rail categories (Sz, IR, IC…); [] = all.
    var railKinds: [String] = []
    var delay: DelayFilter = .all
    var speed: SpeedFilter = .all
    var nearMeKm: Double?
    var sort: VehicleSort = .route
    var stops: Bool = true
    var onlyWatched: Bool = false
    var shape: Bool = true
    var rstops: Bool = false
    var labels: Bool = false
    var follow: Bool = false
    /// Live congestion layer.
    var traffic: Bool = true
    /// The other vehicles stay visible while one is followed.
    var others: Bool = true

    static let `default` = FilterState()
    static let maxWatched = 12
    /// Late from this (s) — as in the statistics.
    static let lateS: Double = 300

    init() {}

    private enum CodingKeys: String, CodingKey {
        case vq, watch, routes, modes, operators, railKinds, delay, speed, nearMeKm, sort
        case stops, onlyWatched, shape, rstops, labels, follow, traffic, others, type
    }

    /// Old saved filters carry `type` (bus / tram); it becomes the `modes` filter.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FilterState.default
        vq = (try? c.decodeIfPresent(String.self, forKey: .vq)) ?? d.vq
        watch = (try? c.decodeIfPresent([String].self, forKey: .watch)) ?? d.watch
        routes = (try? c.decodeIfPresent([String].self, forKey: .routes)) ?? d.routes
        operators = (try? c.decodeIfPresent([String].self, forKey: .operators)) ?? d.operators
        railKinds = (try? c.decodeIfPresent([String].self, forKey: .railKinds)) ?? d.railKinds
        delay = (try? c.decodeIfPresent(DelayFilter.self, forKey: .delay)) ?? d.delay
        speed = (try? c.decodeIfPresent(SpeedFilter.self, forKey: .speed)) ?? d.speed
        nearMeKm = try? c.decodeIfPresent(Double.self, forKey: .nearMeKm)
        sort = (try? c.decodeIfPresent(VehicleSort.self, forKey: .sort)) ?? d.sort
        stops = (try? c.decodeIfPresent(Bool.self, forKey: .stops)) ?? d.stops
        onlyWatched = (try? c.decodeIfPresent(Bool.self, forKey: .onlyWatched)) ?? d.onlyWatched
        shape = (try? c.decodeIfPresent(Bool.self, forKey: .shape)) ?? d.shape
        rstops = (try? c.decodeIfPresent(Bool.self, forKey: .rstops)) ?? d.rstops
        labels = (try? c.decodeIfPresent(Bool.self, forKey: .labels)) ?? d.labels
        follow = (try? c.decodeIfPresent(Bool.self, forKey: .follow)) ?? d.follow
        traffic = (try? c.decodeIfPresent(Bool.self, forKey: .traffic)) ?? d.traffic
        others = (try? c.decodeIfPresent(Bool.self, forKey: .others)) ?? d.others
        if let modes = try? c.decodeIfPresent([TransitMode].self, forKey: .modes) {
            self.modes = modes
        } else {
            switch try? c.decodeIfPresent(String.self, forKey: .type) {
            case "bus": modes = [.bus]
            case "tram": modes = [.tram]
            default: modes = []
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vq, forKey: .vq)
        try c.encode(watch, forKey: .watch)
        try c.encode(routes, forKey: .routes)
        try c.encode(modes, forKey: .modes)
        try c.encode(operators, forKey: .operators)
        try c.encode(railKinds, forKey: .railKinds)
        try c.encode(delay, forKey: .delay)
        try c.encode(speed, forKey: .speed)
        try c.encode(nearMeKm, forKey: .nearMeKm)
        try c.encode(sort, forKey: .sort)
        try c.encode(stops, forKey: .stops)
        try c.encode(onlyWatched, forKey: .onlyWatched)
        try c.encode(shape, forKey: .shape)
        try c.encode(rstops, forKey: .rstops)
        try c.encode(labels, forKey: .labels)
        try c.encode(follow, forKey: .follow)
        try c.encode(traffic, forKey: .traffic)
        try c.encode(others, forKey: .others)
    }

    /// How many real filters narrow the visible vehicles. Display toggles
    /// (stops, shape, labels) are not filters.
    var activeCount: Int {
        [
            !routes.isEmpty, !watch.isEmpty, !modes.isEmpty, !operators.isEmpty, !railKinds.isEmpty,
            delay != .all, speed != .all, nearMeKm != nil,
        ].filter { $0 }.count
    }

    var isActive: Bool { activeCount > 0 }
}
