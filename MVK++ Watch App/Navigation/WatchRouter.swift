//
//  WatchRouter.swift
//  MVK++ Watch App
//

import Combine
import Foundation
import SwiftUI

/// One run to follow, from wherever the rider found it: an arrival row, a
/// vehicle on the map, a ride.
struct TripRef: Hashable {
    let tripId: String
    let vehicleId: String?
    let route: String
    let color: String
    let textColor: String
    let headsign: String
    let delaySec: Int?
    /// The stop the rider found it at, so "Felszálltam" knows where they got on.
    let stopId: String?
    let stopName: String?

    init(arrival: ArrivalItem, stopId: String?, stopName: String?) {
        tripId = arrival.tripId
        vehicleId = arrival.vehicle?.id
        route = arrival.route
        color = arrival.color
        textColor = arrival.text
        headsign = arrival.headsign
        delaySec = arrival.delaySec
        self.stopId = stopId
        self.stopName = stopName
    }

    init(vehicle: LiveVehicle) {
        tripId = vehicle.tripId
        vehicleId = vehicle.id
        route = vehicle.routeShort
        color = vehicle.routeColor
        textColor = vehicle.routeText
        headsign = vehicle.headsign
        delaySec = (vehicle.liveDelaySec ?? vehicle.delaySec).map { Int($0) }
        stopId = nil
        stopName = nil
    }

    init(ride: WatchRideSnapshot) {
        tripId = ride.tripId
        vehicleId = ride.vehicleId
        route = ride.route
        color = ride.color
        textColor = ride.textColor
        headsign = ride.headsign
        delaySec = ride.delaySec
        stopId = ride.boardedStopId
        stopName = ride.boardedStopName
    }
}

/// Every screen the watch can push.
enum WatchRoute: Hashable {
    case stop(String)
    case trip(TripRef)
    case ride
    /// "Felszálltam" without a run picked yet: the departures around the rider.
    case boardPicker
    /// "Hol szállsz le?" for a run the rider just got on.
    case boardDestination(TripRef)
    case map
    case timetable
    case timetableRoute(TimetableRoute)
    case timetableStops(routeId: String, dir: String)
    case disruptions
    case news
    case newsItem(NewsItem)
    case settings
    case search
}

/// The top-level pages, swiped vertically.
enum WatchPage: Hashable {
    case watchlist, nearby, more
}

/// Owns the navigation path, so deep links, intents and nested screens can
/// all move the rider without threading bindings through every view.
@MainActor
final class WatchRouter: ObservableObject {
    static let shared = WatchRouter()

    @Published var path: [WatchRoute] = []
    @Published var page: WatchPage = .watchlist

    func push(_ route: WatchRoute) {
        path.append(route)
    }

    /// Replaces whatever is open with one screen.
    func show(_ route: WatchRoute) {
        path = [route]
    }

    func popToRoot() {
        path.removeAll()
    }

    func open(_ link: DeepLink) {
        switch link {
        case .stop(let stopId), .watchlist(let stopId):
            page = .watchlist
            show(.stop(stopId))
        case .trip(let tripId, let vehicleId):
            show(.trip(TripRef(tripId: tripId, vehicleId: vehicleId)))
        case .ride:
            show(WatchLink.shared.ride.map { $0.ended ? .boardPicker : .ride } ?? .boardPicker)
        case .disruptions:
            show(.disruptions)
        case .home, .kiosk:
            popToRoot()
        case .tab(let tab):
            switch tab {
            case .map: show(.map)
            case .timetable: show(.timetable)
            case .multistop:
                page = .watchlist
                popToRoot()
            case .parking, .planner, .stats:
                popToRoot()
            }
        }
    }
}

private extension TripRef {
    /// A run known only by its IDs, from a link: the follow screen fills in
    /// the rest from the trip-progress feed.
    init(tripId: String, vehicleId: String?) {
        self.tripId = tripId
        self.vehicleId = vehicleId
        route = ""
        color = ""
        textColor = ""
        headsign = ""
        delaySec = nil
        stopId = nil
        stopName = nil
    }
}
