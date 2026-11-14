//
//  APIClient+Kiosk.swift
//  MVK++ Phone App
//

import Foundation

/// One departure on the stop board, with the v3 fields the kiosk shows
/// (platform, notices, forecast, predicted vehicle).
struct KioskArrival: Decodable, Hashable {
    struct Vehicle: Decodable, Hashable {
        let id: String
    }

    struct PredictedVehicle: Decodable, Hashable {
        let id: String
        let confidence: Double?
        let method: String?
    }

    let route: String
    let color: String
    let text: String
    let headsign: String
    let time: String
    let etaMin: Double
    let delaySec: Double?
    let tripId: String
    let vehicle: Vehicle?
    let currentStopName: String?
    let progressDesc: String?
    let measuredDelaySec: Double?
    let predictedVehicle: PredictedVehicle?
    let cancelled: Bool?
    let forecastDelaySec: Double?
    let forecastUpperSec: Double?
    let mode: String?
    let trainNo: String?
    let trainName: String?
    let platform: String?
    let platformChanged: Bool?
    let platformPredicted: Bool?
    let notices: [String]?

    var isCancelled: Bool { cancelled == true }
    var isRail: Bool { mode == "rail" }

    /// The tile text: "IC 582" for a train, the route number elsewhere.
    var tileText: String {
        if isRail, let trainNo, !trainNo.isEmpty { return "\(route) \(trainNo)" }
        return route
    }

    /// The row title: a train's name too ("TOKAJ → Budapest-Nyugati").
    var title: String {
        if let trainName, !trainName.isEmpty { return "\(trainName) → \(headsign)" }
        return headsign
    }

    /// The vehicle label: a Volán bus's plate; none for a train (its number
    /// is on the tile).
    var vehicleLabel: String? {
        guard let vehicle, !isRail else { return nil }
        return TransitModes.displayVehicleId(vehicle.id)
    }
}

struct KioskBoard: Decodable {
    struct StopInfo: Decodable {
        let id: String
        let code: String?
        let name: String?
    }

    let stop: StopInfo
    let now: Double?
    let arrivals: [KioskArrival]
}

extension APIClient {

    /// `/live/arrivals` for the board key (`modes~merge`), as the web's
    /// `getArrivals(stopId, limit, board)` asks for it.
    func kioskBoard(stopId: String, limit: Int, boardKey: String) async throws -> KioskBoard {
        let parts = boardKey.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        var items = [
            URLQueryItem(name: "stop", value: stopId),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "modes", value: parts.first ?? ""),
        ]
        if parts.count > 1, !parts[1].isEmpty {
            items.append(URLQueryItem(name: "merge", value: parts[1]))
        }
        return try await request(path: "/live/arrivals", queryItems: items)
    }
}
