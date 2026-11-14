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

extension TripJournalEntry {
    private enum CodingKeys: String, CodingKey {
        case vehicleId, samples, firstSeen, lastSeen, startDelaySec, endDelaySec, actualStart, actualEnd, status, stopsSeen, stopsTotal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            vehicleId: c.lenientString(.vehicleId),
            samples: c.lenientInt(.samples) ?? 0,
            firstSeen: c.lenientDouble(.firstSeen),
            lastSeen: c.lenientDouble(.lastSeen),
            startDelaySec: c.lenientInt(.startDelaySec),
            endDelaySec: c.lenientInt(.endDelaySec),
            actualStart: c.lenientDouble(.actualStart),
            actualEnd: c.lenientDouble(.actualEnd),
            status: c.lenientString(.status),
            stopsSeen: c.lenientInt(.stopsSeen),
            stopsTotal: c.lenientInt(.stopsTotal)
        )
    }
}

struct TripJournalResponse: Decodable {
    let date: String
    let count: Int
    let source: String
    /// Keyed by trip ID.
    let trips: [String: TripJournalEntry]

    private enum CodingKeys: String, CodingKey { case date, count, source, trips }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        count = c.lenientInt(.count) ?? 0
        source = c.lenientString(.source) ?? ""
        trips = Dictionary(lenient: try c.decode([String: Lenient<TripJournalEntry>].self, forKey: .trips))
    }
}
