//
//  OfflineDepartures.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// Answers "mikor jön a következő" from the downloaded timetable alone.
///
/// These are scheduled times, not predictions: `live` is false and `delaySec`
/// is nil on every row, which is the honest answer when there is no realtime
/// feed to compare against. The UI reads those two fields to label the board
/// as menetrend szerinti, so nothing here pretends to know more than it does.
enum OfflineDepartures {

    /// How far back a departure still counts. A bus a minute late is the one
    /// the rider is running for; one ten minutes gone is noise.
    private static let graceSec = 90

    /// The next scheduled calls at `stopId`, oldest first.
    ///
    /// Three service days are consulted, because a service day is not a
    /// calendar day. Just after midnight the runs a rider wants are still filed
    /// under yesterday (as 24:15, 25:02), and late in the evening the tail of
    /// the list belongs to tomorrow morning.
    static func calls(
        stopId: String,
        at now: Date = Date(),
        limit: Int = 8
    ) -> [OfflineCall] {
        let today = ServiceDay.ymd(now)
        let nowSec = ServiceDay.secondsSinceMidnight(now)
        let fromSec = nowSec - graceSec

        var calls: [OfflineCall] = []

        // Yesterday's after-midnight tail, rebased onto today's clock.
        if let yesterday = OfflineScheduleStore.index(ServiceDay.shifted(today, byDays: -1)) {
            calls += yesterday.calls(
                stopId: stopId, fromSec: fromSec, dayOffsetSec: -86_400, limit: limit
            )
        }

        if let index = OfflineScheduleStore.index(today) {
            calls += index.calls(stopId: stopId, fromSec: fromSec, limit: limit)
        }

        // Only worth a third lookup when today has run dry.
        if calls.count < limit, let tomorrow = OfflineScheduleStore.index(ServiceDay.shifted(today, byDays: 1)) {
            calls += tomorrow.calls(
                stopId: stopId, fromSec: fromSec, dayOffsetSec: 86_400, limit: limit - calls.count
            )
        }

        return calls
            .sorted { $0.effectiveSec < $1.effectiveSec }
            .prefix(limit)
            .map { $0 }
    }

    /// The same departures as `ArrivalItem`s, so every screen keeps rendering
    /// one arrival type whether the numbers came from the gateway or the pack.
    static func arrivals(
        stopId: String,
        at now: Date = Date(),
        limit: Int = 8
    ) -> [ArrivalItem] {
        let nowSec = ServiceDay.secondsSinceMidnight(now)
        return calls(stopId: stopId, at: now, limit: limit).map { call in
            ArrivalItem(
                route: call.route.short,
                color: call.route.color,
                text: call.route.text,
                headsign: call.headsign,
                time: call.clock,
                // Rounded down, matching the gateway: "3 perc" means the bus
                // has not gone yet, not that it is three away.
                etaMin: max(0, (call.effectiveSec - nowSec) / 60),
                delaySec: nil,
                live: false,
                tripId: call.tripId
            )
        }
    }

    /// When a call is due, as an absolute moment. The widget counts down
    /// between refreshes and needs the second, not the rounded minute.
    static func due(_ call: OfflineCall, at now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: now).addingTimeInterval(Double(call.effectiveSec))
    }

    /// True when the pack can answer for this stop at all — the caller uses it
    /// to choose between "nincs kapcsolat" and "ma már nem indul járat".
    static func knowsStop(_ stopId: String, at now: Date = Date()) -> Bool {
        OfflineScheduleStore.index(ServiceDay.ymd(now))?.stopTimes[stopId] != nil
    }

    /// The routes calling at a stop, for the empty state.
    static func routeShorts(stopId: String, at now: Date = Date()) -> [String] {
        OfflineScheduleStore.index(ServiceDay.ymd(now))?.routeShorts(stopId: stopId) ?? []
    }

    /// Whether a schedule-only board is available right now, at all.
    static var isAvailable: Bool {
        OfflineScheduleStore.hasSchedule(for: ServiceDay.ymd())
    }
}
