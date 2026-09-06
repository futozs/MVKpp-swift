//
//  CancelledTrips.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// A run the operator dropped for the day, from `/live/cancelled`.
/// `known == false` means the cancellation names a trip the loaded GTFS feed
/// has no record of — show the ID, but expect the descriptive fields to be nil.
struct CancelledTrip: Decodable, Hashable, Identifiable {
    let tripId: String
    let known: Bool
    let routeId: String
    let routeShort: String
    let routeColor: String
    let routeText: String
    let dir: String
    let headsign: String
    let departure: String?
    let departureSec: Int?
    let arrival: String?
    let originName: String?
    let destinationName: String?

    var id: String { tripId }
}

struct CancelledTripsResponse: Decodable {
    let date: String
    let count: Int
    /// The upstream cancellation feed is older than the gateway's freshness
    /// window — the list may be incomplete.
    let stale: Bool
    /// Served from the archive rather than live.
    let archived: Bool
    let fetchedAt: String?
    let tripIds: [String]
    let trips: [CancelledTrip]
}
