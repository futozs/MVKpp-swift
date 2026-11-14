//
//  APIClient+Timetable.swift
//  MVK++ (shared)
//

import Foundation

/// One measured stop event of a run (`/engine/trip`).
struct TripActualEvent: Decodable, Hashable {
    let stop_id: String
    let arr: Double
    let dep: Double?
    let delay_s: Int
    /// 3 = estimated from the path (the vehicle went quiet before the terminus).
    let src: Int
}

struct TripActualsResponse: Decodable {
    let events: [TripActualEvent]?
}

extension APIClient {
    /// The enabled modes' routes for a day (MVK, Volán, rail).
    func timetableRoutes(date: String?, modes: String) async throws -> TimetableRoutesResponse {
        try await request(path: "/gtfs/timetable/routes", queryItems: modesQuery(modes, date: date))
    }

    func cancelledTrips(date: String?, modes: String) async throws -> CancelledTripsResponse {
        try await request(path: "/live/cancelled", queryItems: modesQuery(modes, date: date))
    }

    func tripJournal(date: String?, modes: String) async throws -> TripJournalResponse {
        try await request(path: "/gtfs/trip-journal", queryItems: modesQuery(modes, date: date))
    }

    /// When the vehicle actually reached each stop of a run.
    func tripActuals(dateYmd: String, tripId: String) async throws -> TripActualsResponse {
        try await request(path: "/engine/trip", queryItems: [
            URLQueryItem(name: "date", value: dateYmd),
            URLQueryItem(name: "trip", value: tripId),
        ])
    }

    private func modesQuery(_ modes: String, date: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "modes", value: modes)]
        if let date, !date.isEmpty { items.append(URLQueryItem(name: "date", value: date)) }
        return items
    }
}
