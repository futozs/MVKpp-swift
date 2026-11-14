//
//  DepartureSnapshot.swift
//  MVK++ (shared by the Phone and Watch widgets)
//

import Foundation

/// One departure, frozen at fetch time.
///
/// The ETA is stored as an absolute `due` date rather than a minute count, so
/// every timeline entry between two network refreshes can recompute an honest
/// countdown instead of showing the same stale number for five minutes.
struct DepartureSnapshot: Identifiable, Hashable {
    let id: String
    let route: String
    let color: String
    let textColor: String
    let headsign: String
    let due: Date
    let delaySec: Int?
    let isLive: Bool
    let vehicleId: String?
    let tripId: String

    func minutes(at date: Date) -> Int {
        max(0, Int(due.timeIntervalSince(date) / 60))
    }

    /// Once a bus is a minute past due it is gone, not "0 perc".
    func hasDeparted(at date: Date) -> Bool {
        due.timeIntervalSince(date) < -60
    }
}

extension DepartureSnapshot {
    /// `reference` is the gateway's own clock (`StopArrivalsResponse.now`),
    /// which the ETA counts from.
    init(_ arrival: ArrivalItem, reference: Date) {
        self.init(
            id: arrival.id,
            route: arrival.route,
            color: arrival.color.isEmpty ? "1FB574" : arrival.color,
            textColor: arrival.text.isEmpty ? "FFFFFF" : arrival.text,
            headsign: arrival.headsign,
            due: reference.addingTimeInterval(Double(arrival.etaMin) * 60),
            delaySec: arrival.delaySec,
            isLive: arrival.live,
            vehicleId: arrival.vehicle?.id,
            tripId: arrival.tripId
        )
    }

    static func list(_ response: StopArrivalsResponse, now: Date = Date()) -> [DepartureSnapshot] {
        let reference = response.now > 0 ? Date(timeIntervalSince1970: response.now) : now
        return response.arrivals.filter { !$0.isCancelled }.map { DepartureSnapshot($0, reference: reference) }
    }
}
