//
//  RideBoarding.swift
//  MVK++ Phone App
//

import Foundation

@MainActor
enum RideBoarding {
    /// Starts a ride (the map then follows the bus). For a detected boarding
    /// `since` is where and when the phone stood next to the bus before they
    /// set off — the answer can come minutes later, phone in a pocket.
    static func board(_ info: BoardInfo, detected: RideSource, since: BoardingSpot? = nil, store: RideStore = .shared) {
        guard store.active == nil else { return }
        let ageS = since.map { max(0, Date().timeIntervalSince1970 - $0.at) } ?? 0
        let boardedAt = (RealtimeClient.shared.serverNow - ageS).rounded()
        store.startRide(ActiveRide(
            id: UUID().uuidString.lowercased(),
            serviceDate: ServiceClock.at(Int(boardedAt)).iso,
            vehicleId: info.vehicleId,
            tripId: info.tripId,
            route: info.route,
            headsign: info.headsign,
            color: info.color,
            text: info.text,
            boardedAt: boardedAt,
            boardNear: since.map { RidePoint(lat: $0.lat, lon: $0.lon) },
            fromIdx: nil,
            fromStopId: nil,
            fromStopName: nil,
            delayAtBoardS: nil,
            destIdx: nil,
            detected: detected
        ))
        RideHaptics.boarded()
    }

    static func board(vehicle v: LiveVehicle, detected: RideSource, since: BoardingSpot? = nil) {
        board(
            BoardInfo(tripId: v.tripId, vehicleId: v.id, route: v.routeShort, color: v.routeColor, text: v.routeText, headsign: v.headsign),
            detected: detected,
            since: since
        )
    }
}
