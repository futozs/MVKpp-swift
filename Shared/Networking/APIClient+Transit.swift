//
//  APIClient+Transit.swift
//  MVK++ (shared)
//

import Foundation

extension APIClient {
    /// A to B directly (e.g. Miskolc-Tiszai → Füzesabony), in the enabled modes.
    func relation(from: String, to: String, limit: Int = 8) async throws -> RelationBoardResponse {
        try await request(path: "/engine/transit/relation", queryItems: [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "modes", value: TransitMode.param()),
        ])
    }

    /// A train by number: today's or tomorrow's run, stop by stop.
    func train(no: String) async throws -> TrainDetailResponse {
        try await request(path: "/engine/transit/train", queryItems: [URLQueryItem(name: "no", value: no)])
    }

    /// Any mode's trip stop by stop (the timetable of the vehicle followed on the map).
    func tripDetail(tripId: String) async throws -> TrainDetailResponse {
        try await request(path: "/engine/transit/trip", queryItems: [URLQueryItem(name: "trip", value: tripId)])
    }

    /// Stops, stations and train numbers in every enabled mode.
    func searchTransit(_ q: String) async throws -> TransitSearchResponse {
        try await request(path: "/engine/transit/search", queryItems: [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "modes", value: TransitMode.param()),
        ])
    }
}
