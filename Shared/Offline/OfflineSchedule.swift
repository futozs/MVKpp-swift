//
//  OfflineSchedule.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// A route, flattened for storage. `Route` decodes from two different gateway
/// shapes and is deliberately not `Encodable`; this is the keyed form that
/// goes into an offline pack.
struct OfflineRoute: Codable, Hashable, Sendable {
    let id: String
    let short: String
    let long: String
    let type: String
    let color: String
    let text: String

    private enum CodingKeys: String, CodingKey {
        case id = "i", short = "s", long = "l", type = "y", color = "c", text = "t"
    }

    init(_ route: Route) {
        id = route.id
        short = route.short
        long = route.long
        type = route.type
        color = route.color
        text = route.text
    }

    var asRoute: Route {
        Route(id: id, short: short, long: long, type: type, color: color, text: text)
    }
}

/// One run, stripped to what a departure board needs. `headsign` indexes the
/// pack's string table — the same two dozen destinations repeat across
/// thousands of trips, and storing them inline triples the file.
struct OfflineTrip: Codable, Hashable, Sendable {
    let id: String
    let route: Int
    let headsign: Int
    let dir: String

    private enum CodingKeys: String, CodingKey {
        case id = "i", route = "r", headsign = "h", dir = "d"
    }
}

/// Every scheduled call at every stop for one service day, indexed by stop.
///
/// The layout is chosen for size, because this is written once and read on
/// every widget refresh: routes, headsigns and trips are tables, and the
/// per-stop entries are flat `[tripIndex, secondsSinceMidnight, …]` pairs
/// sorted by time. A weekday comes to roughly 180 KB compressed.
///
/// Seconds may exceed 86 400: GTFS files after-midnight service under the day
/// it started, and that is exactly the run a rider is looking for at 00:30.
struct OfflineScheduleIndex: Codable, Sendable {
    let date: String
    let feedVersion: String
    let routes: [OfflineRoute]
    let strings: [String]
    let trips: [OfflineTrip]
    let stopTimes: [String: [Int]]

    private enum CodingKeys: String, CodingKey {
        case date = "d", feedVersion = "v", routes = "r", strings = "s", trips = "t", stopTimes = "st"
    }

    var stopCount: Int { stopTimes.count }
    var tripCount: Int { trips.count }

    func headsign(_ index: Int) -> String {
        strings.indices.contains(index) ? strings[index] : ""
    }

    // MARK: - Lookup

    /// Scheduled calls at `stopId` at or after `fromSec`, oldest first.
    ///
    /// `dayOffsetSec` shifts the result onto the caller's clock: yesterday's
    /// after-midnight runs are queried with -86 400 so a 24:15 departure lands
    /// at 00:15 today.
    func calls(
        stopId: String,
        fromSec: Int,
        dayOffsetSec: Int = 0,
        limit: Int
    ) -> [OfflineCall] {
        guard limit > 0, let flat = stopTimes[stopId] else { return [] }

        var result: [OfflineCall] = []
        var index = 0
        while index + 1 < flat.count, result.count < limit {
            let tripIndex = flat[index]
            let scheduledSec = flat[index + 1]
            index += 2

            let effective = scheduledSec + dayOffsetSec
            guard effective >= fromSec else { continue }
            guard trips.indices.contains(tripIndex) else { continue }

            let trip = trips[tripIndex]
            guard routes.indices.contains(trip.route) else { continue }

            result.append(
                OfflineCall(
                    tripId: trip.id,
                    dir: trip.dir,
                    headsign: headsign(trip.headsign),
                    route: routes[trip.route],
                    scheduledSec: scheduledSec,
                    effectiveSec: effective
                )
            )
        }
        return result
    }

    /// Which routes call at a stop at all — used to say something useful about
    /// a stop that has finished for the day.
    func routeShorts(stopId: String) -> [String] {
        guard let flat = stopTimes[stopId] else { return [] }
        var seen = Set<String>()
        var order: [String] = []
        for index in stride(from: 0, to: flat.count - 1, by: 2) {
            let tripIndex = flat[index]
            guard trips.indices.contains(tripIndex) else { continue }
            let route = trips[tripIndex].route
            guard routes.indices.contains(route) else { continue }
            let short = routes[route].short
            if seen.insert(short).inserted { order.append(short) }
        }
        return order
    }
}

/// One scheduled call, resolved out of the index tables.
struct OfflineCall: Hashable, Sendable {
    let tripId: String
    let dir: String
    let headsign: String
    let route: OfflineRoute
    /// As filed in the feed — may run past 24:00.
    let scheduledSec: Int
    /// On the reader's clock, after the day offset is applied.
    let effectiveSec: Int

    /// "05:20", wrapped into a normal clock face.
    var clock: String {
        ScheduleTime.format(minutesPastMidnight: scheduledSec / 60)
    }
}

/// What is on the device, and how current it is.
struct OfflineScheduleManifest: Codable, Hashable, Sendable {
    /// The GTFS release the pack was built from. A feed change invalidates it:
    /// times move, and a stale board is worse than no board.
    var feedVersion: String
    /// Service days present, ascending.
    var days: [String]
    var builtAt: Date
    var bytes: Int64

    static let empty = OfflineScheduleManifest(feedVersion: "", days: [], builtAt: .distantPast, bytes: 0)

    var isEmpty: Bool { days.isEmpty }

    func covers(_ ymd: String) -> Bool { days.contains(ymd) }

    /// The last day the pack can answer for, which is what the rider actually
    /// wants to know ("meddig van meg").
    var lastDay: String? { days.max() }
}
