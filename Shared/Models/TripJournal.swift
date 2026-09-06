//
//  TripJournal.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// What the gateway actually observed for one run over the course of the day:
/// which vehicle served it, when it really started and finished, and how far
/// off schedule those moments were. This is the only source for runs that have
/// already ended — the live feed drops them.
struct TripJournalEntry: Decodable, Hashable {
    let vehicleId: String?
    let samples: Int
    let firstSeen: Double?
    let lastSeen: Double?
    /// Seconds; positive = late.
    let startDelaySec: Int?
    let endDelaySec: Int?
    let actualStart: Double?
    let actualEnd: Double?
    let status: String?
    let stopsSeen: Int?
    let stopsTotal: Int?
}

struct TripJournalResponse: Decodable {
    let date: String
    let count: Int
    let source: String
    /// Keyed by trip ID.
    let trips: [String: TripJournalEntry]
}
