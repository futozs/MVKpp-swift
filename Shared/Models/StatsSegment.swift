//
//  StatsSegment.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// One measured hop between two consecutive stops.
struct SegmentLeg: Decodable, Hashable {
    let from: String
    let to: String
    /// Scheduled seconds.
    let schedS: Int
    /// Median measured seconds.
    let p50S: Int
    /// 85th percentile — the "allow this much" figure.
    let p85S: Int
    let samples: Int
    let source: String
}

/// How long a stop-to-stop journey actually takes, from the gateway's own
/// measurements rather than the timetable.
///
/// Used when the rider asks about a moment in the past: the live planner
/// cannot answer for yesterday, but the warehouse can.
struct SegmentEstimate: Decodable {
    let from: String
    let to: String
    let at: String
    let daytype: Int
    let school: Bool
    let via: String
    let routeShort: String?
    let routeColor: String?
    let headsign: String?
    /// The schedule used was the one in force on that day, not an approximation.
    let scheduleExact: Bool
    let stopsBetween: Int
    let schedS: Int
    let p50S: Int
    let p85S: Int
    let rawP50S: Int
    let liveFactor: Double?
    let liveSamples: Int
    let samples: Int
    let coverage: Double
    let confidence: String
    let legs: [SegmentLeg]
}

/// Average lateness for boarding one route at one stop.
struct RouteDelayInfo: Decodable, Hashable {
    let avgDelaySec: Double?
    let samples: Int
}

struct RouteDelaysResponse: Decodable {
    let results: [RouteDelayInfo]
}

struct RouteDelayLeg: Encodable {
    let routeShort: String
    let stopId: String
}

struct RouteDelaysRequest: Encodable {
    let at: String
    let legs: [RouteDelayLeg]
}

/// The warehouse is a separate service behind the gateway and can be down
/// while everything else works — worth distinguishing so the UI can say
/// "no measurements" instead of "error".
struct StatsUnavailableError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}
