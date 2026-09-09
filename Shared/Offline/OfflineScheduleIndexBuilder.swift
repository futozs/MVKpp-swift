//
//  OfflineScheduleIndexBuilder.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// Folds a day's worth of `/gtfs/timetable` responses into one per-stop index.
///
/// The gateway serves the timetable the way it is read — one route and
/// direction at a time, stops across the top and runs down the side. A
/// departure board needs the transpose of that, and transposing 114 responses
/// on every widget refresh is not something a widget has time for. So it
/// happens once, at download.
struct OfflineScheduleIndexBuilder: Sendable {

    private let date: String
    private let feedVersion: String

    private var routes: [OfflineRoute] = []
    private var routeIndex: [String: Int] = [:]
    private var strings: [String] = []
    private var stringIndex: [String: Int] = [:]
    private var trips: [OfflineTrip] = []
    private var seenTrips: Set<String> = []
    private var stopTimes: [String: [Int]] = [:]

    init(date: String, feedVersion: String) {
        self.date = date
        self.feedVersion = feedVersion
    }

    var routeCount: Int { routes.count }
    var tripCount: Int { trips.count }

    mutating func add(_ table: TimetableResponse) {
        let routeRef = intern(route: table.route)
        let stopIds = table.stops.map(\.id)

        for trip in table.trips {
            // A run can appear under more than one direction listing when the
            // feed's headsigns disagree; the first one wins rather than
            // doubling the stop's board.
            guard seenTrips.insert(trip.tripId).inserted else { continue }

            let tripRef = trips.count
            trips.append(
                OfflineTrip(
                    id: trip.tripId,
                    route: routeRef,
                    headsign: intern(string: trip.headsign.isEmpty ? table.headsign : trip.headsign),
                    dir: table.dir
                )
            )

            // `times` is aligned with `stops`; nil means the run skips it.
            for (position, clock) in trip.times.enumerated() {
                guard position < stopIds.count,
                      let clock,
                      let minutes = ScheduleTime.minutes(clock)
                else { continue }
                stopTimes[stopIds[position], default: []].append(contentsOf: [tripRef, minutes * 60])
            }
        }
    }

    func build() -> OfflineScheduleIndex {
        // Sorted once here so every lookup can stop at the first hit past now
        // instead of scanning and sorting a stop's whole day.
        let sorted = stopTimes.mapValues { flat -> [Int] in
            let pairs = stride(from: 0, to: flat.count - 1, by: 2)
                .map { (trip: flat[$0], sec: flat[$0 + 1]) }
                .sorted { $0.sec < $1.sec }
            return pairs.flatMap { [$0.trip, $0.sec] }
        }

        return OfflineScheduleIndex(
            date: date,
            feedVersion: feedVersion,
            routes: routes,
            strings: strings,
            trips: trips,
            stopTimes: sorted
        )
    }

    // MARK: - String and route tables

    private mutating func intern(route: Route) -> Int {
        if let existing = routeIndex[route.id] { return existing }
        let position = routes.count
        routes.append(OfflineRoute(route))
        routeIndex[route.id] = position
        return position
    }

    private mutating func intern(string: String) -> Int {
        if let existing = stringIndex[string] { return existing }
        let position = strings.count
        strings.append(string)
        stringIndex[string] = position
        return position
    }
}
