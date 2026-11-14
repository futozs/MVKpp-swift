//
//  WatchSyncModels.swift
//  MVK++ (shared by the Phone, Watch and Widget targets)
//

import Foundation

/// The ride the rider is on, reduced to what fits on a wrist.
///
/// The phone's ride store owns the ride and sends this whenever it changes;
/// the watch only draws it. When the phone cannot be reached the watch builds
/// the same snapshot itself from the trip-progress feed (`source == .watch`),
/// so every watch surface — the app, the complications — reads one shape.
struct WatchRideSnapshot: Codable, Hashable {
    enum Source: String, Codable {
        case phone, watch
    }

    var rideId: String
    var tripId: String
    var vehicleId: String?
    /// Route short name, as on the tile ("1", "21A", "IC 582").
    var route: String
    /// Bare hex, no "#".
    var color: String
    var textColor: String
    var headsign: String
    /// "tram", "bus", "coach" or "rail"; nil for MVK when unknown.
    var mode: String?
    var boardedStopId: String?
    var boardedStopName: String?
    /// Where the rider gets off; nil means "until the end of the trip".
    var destinationStopId: String?
    var destinationStopName: String?
    var nextStopId: String?
    var nextStopName: String?
    /// Unix seconds the vehicle is expected at the next stop.
    var nextStopAt: Double?
    /// Stops still to come up to and including the destination (or the
    /// terminus without one).
    var stopsLeft: Int?
    /// Positive = late, negative = early, nil = no live match.
    var delaySec: Int?
    /// 0…1 of the rider's own leg.
    var progress: Double?
    /// Unix seconds.
    var boardedAt: Double
    /// Unix seconds of the data behind this snapshot.
    var updatedAt: Double
    /// The ride is over (got off, or the trip ended). Sent once so the watch
    /// can say so, then the phone clears it.
    var ended: Bool
    var source: Source

    var nextStopDate: Date? { nextStopAt.map { Date(timeIntervalSince1970: $0) } }

    /// The next stop is where the rider gets off.
    var isGetOffNext: Bool { !ended && stopsLeft == 1 }
}

/// "Felszálltam" asked for on the watch: which run, and optionally where the
/// rider got on and wants to get off.
struct WatchRideRequest: Codable, Hashable {
    var tripId: String
    var vehicleId: String?
    var route: String
    var color: String
    var textColor: String
    var headsign: String
    var boardStopId: String?
    var boardStopName: String?
    var destinationStopId: String?
    var destinationStopName: String?
}

/// What the watch asks the phone's ride store to do.
enum WatchRideCommand: Hashable {
    /// Start a ride. `nil` comes from a control or a deep link that knows no
    /// trip yet: the phone should offer its own boarding flow.
    case start(WatchRideRequest?)
    case end
}

/// The phone's settings the watch follows, so the rider sets them once.
struct WatchSettings: Codable, Hashable {
    var modes: [TransitMode]
    var merge: StopMerge
    var lineFavorites: [FavoriteLine]
    var predictedVehicle: Bool

    static let `default` = WatchSettings(modes: [.tram, .bus], merge: .all, lineFavorites: [], predictedVehicle: true)

    var boardKey: String { TransitModes.boardKey(modes, merge: merge) }
    var modesParam: String { TransitModes.param(modes) }
}

/// The WatchConnectivity vocabulary both apps speak.
///
/// Application context (latest state, delivered even if the other app is
/// not running): the watchlist keys, `settings` and `ride`. Messages (only
/// while reachable): `action` with an optional `request`, and live `ride`
/// pushes from the phone.
enum WatchSyncKey {
    static let stopIds = "stopIds"
    static let nearestFirst = "nearestFirstEnabled"
    static let widgetNearest = "widgetNearestEnabled"
    static let widgetStopId = "widgetStopId"
    /// JSON `WatchSettings`, phone → watch.
    static let settings = "settings"
    /// JSON `WatchRideSnapshot`, phone → watch; absent when there is no ride.
    static let ride = "ride"
    /// A `WatchSyncAction` raw value, watch → phone.
    static let action = "action"
    /// JSON `WatchRideRequest` with `action == startRide`.
    static let request = "request"
    /// Reply key: true when the phone took the command.
    static let accepted = "accepted"
}

enum WatchSyncAction: String {
    case startRide, endRide
}

/// The watch keeps the last ride and settings in the App Group so its
/// complications can draw them without the app running.
enum WatchSharedState {
    private static let rideKey = "mvk_watch_ride"
    private static let settingsKey = "mvk_watch_settings"
    private static var suite: UserDefaults { UserDefaults(suiteName: FavoritesStore.appGroupID) ?? .standard }

    static var ride: WatchRideSnapshot? {
        suite.data(forKey: rideKey).flatMap { try? JSONDecoder().decode(WatchRideSnapshot.self, from: $0) }
    }

    static func save(ride: WatchRideSnapshot?) {
        if let ride, let data = try? JSONEncoder().encode(ride) {
            suite.set(data, forKey: rideKey)
        } else {
            suite.removeObject(forKey: rideKey)
        }
    }

    static var settings: WatchSettings {
        suite.data(forKey: settingsKey).flatMap { try? JSONDecoder().decode(WatchSettings.self, from: $0) } ?? .default
    }

    static func save(settings: WatchSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        suite.set(data, forKey: settingsKey)
    }
}

extension Notification.Name {
    /// A `WatchRideCommand` for the phone's ride store, from the watch, a
    /// control or the `mvkpp://ride` link.
    static let mvkRideCommand = Notification.Name("mvk-ride-command")
}
