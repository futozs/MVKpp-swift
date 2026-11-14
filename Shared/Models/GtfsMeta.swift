//
//  GtfsMeta.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// Inclusive `from`…`to` day range, as ISO `yyyy-MM-dd` strings — the same
/// shape the gateway sends, kept as strings so day comparison stays a plain
/// lexicographic test (see `TripStatus.dayRelation`).
struct DateRange: Decodable, Hashable {
    let from: String
    let to: String
    let days: Int?
}

/// `/gtfs/meta.json` — what feed the gateway is currently serving.
struct GtfsMeta: Decodable, Hashable {
    let feedVersion: String
    let stops: Int
    let routes: Int
    let trips: Int
    let shapes: Int?
    /// The days the live schedule covers.
    let serviceRange: DateRange?
    /// Past days still queryable from the archive.
    let archiveRange: DateRange?
    /// Volán and rail in today's schedule: "off", "pending" while the worker
    /// is still building them after a restart, "ready".
    var regional: String? = nil
}
