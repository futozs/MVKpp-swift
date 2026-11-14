//
//  AppNavigation.swift
//  MVK++ Phone App
//

import Combine
import Foundation
import SwiftUI

/// Which tab is showing, which stop is open, and which trip is being followed
/// — persisted so reopening the app lands the rider back where they were.
@MainActor
final class AppNavigation: ObservableObject {

    @Published var tab: AppTab
    @Published var selectedStopId: String?
    @Published var focusTripId: String?
    @Published var focusVehicleId: String?

    /// Which watchlist card the Megállófigyelő should scroll to. That screen
    /// consumes it and clears it, so the same stop can be requested again
    /// later from another widget tap.
    @Published var watchlistFocusStopId: String?

    // MARK: Shell overlays (web `App.tsx` modal state)

    @Published var isNotificationsOpen = false
    @Published var isAccountOpen = false
    @Published var isSettingsOpen = false
    /// "Mai zavarok" — opened from Statisztika and Menetrend.
    @Published var isDisruptionsOpen = false
    /// The stop board kiosk (`/kijelzo?m=…`): the stops it shows, or nil.
    @Published var kioskStopIds: [String]?
    /// A trip picked in "Mai zavarok", for the Menetrend to open. The
    /// timetable consumes it and sets it back to nil.
    @Published var pendingTimetableTrip: TimetableTripRequest?

    /// Which base map is drawn. Lives here rather than in the map view
    /// because Settings offers the same choice.
    @Published var tileLayerId: String {
        didSet {
            guard tileLayerId != oldValue else { return }
            TileLayerCatalog.save(tileLayerId)
        }
    }

    @Published var filters: FilterState {
        didSet {
            guard filters != oldValue else { return }
            ViewStateStore.save(filters)
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let restored = ViewStateStore.initialView()
        // Mid-ride the app opens on the map: the ride panel lives there, and
        // that is where a ride that ended meanwhile is closed.
        tab = RideStore.shared.active != nil ? .map : restored?.tab ?? .map
        selectedStopId = restored?.selectedStopId
        focusTripId = restored?.focusTripId
        focusVehicleId = restored?.focusVehicleId
        filters = ViewStateStore.loadFilters()
        tileLayerId = TileLayerCatalog.saved.id

        // One coalesced write per change burst rather than four separate ones.
        Publishers.CombineLatest4($tab, $selectedStopId, $focusTripId, $focusVehicleId)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { tab, stopId, tripId, vehicleId in
                ViewStateStore.save(
                    ViewStateStore.ViewState(
                        tab: tab,
                        selectedStopId: stopId,
                        focusTripId: tripId,
                        focusVehicleId: vehicleId
                    )
                )
            }
            .store(in: &cancellables)
    }

    var isFollowingTrip: Bool { focusTripId != nil }

    var tileLayer: TileLayerOption { TileLayerCatalog.layer(id: tileLayerId) }

    func focusTrip(_ tripId: String, vehicleId: String? = nil) {
        focusTripId = tripId
        focusVehicleId = vehicleId
    }

    /// From the Menetrend and the Megállófigyelő: a vehicle that has since
    /// moved on to another trip is followed on the trip it runs now, or the
    /// old trip's path and data would show.
    func focusTripOnMap(_ tripId: String, vehicleId: String?, store: TransitStore) {
        let current = vehicleId.flatMap { store.vehicle(id: $0)?.tripId }
        tab = .map
        focusTrip(current.flatMap { $0.isEmpty ? nil : $0 } ?? tripId, vehicleId: vehicleId)
    }

    func exitFocus() {
        focusTripId = nil
        focusVehicleId = nil
    }

    /// Opens a stop on the map, optionally following the vehicle the rider
    /// tapped through from.
    func focusStopOnMap(_ stop: Stop, tripId: String? = nil, vehicleId: String? = nil) {
        selectedStopId = stop.id
        tab = .map
        if let tripId { focusTrip(tripId, vehicleId: vehicleId) }
    }

    /// "Élőben a térképen" (Statisztika, Parkoló): a vehicle running a trip is
    /// followed; otherwise it is pinned and highlighted on the map.
    func focusVehicleOnMap(_ vehicleId: String, vehicle: LiveVehicle?) {
        tab = .map
        if let tripId = vehicle?.tripId, !tripId.isEmpty {
            focusTrip(tripId, vehicleId: vehicleId)
            return
        }
        exitFocus()
        var next = filters
        if !next.watch.contains(vehicleId) { next.watch.append(vehicleId) }
        next.vq = ""
        filters = next
    }

    /// A trip picked in "Mai zavarok" opens in the Menetrend.
    func openTimetableTrip(_ request: TimetableTripRequest) {
        isDisruptionsOpen = false
        pendingTimetableTrip = request
        tab = .timetable
    }

    func clearFilters() {
        filters = .default
    }

    /// Entry point for `mvkpp://` links — today that means a tap on a home
    /// screen widget row, which should land on exactly the stop the rider was
    /// looking at.
    func open(_ link: DeepLink) {
        switch link {
        case .stop(let stopId):
            exitFocus()
            selectedStopId = stopId
            tab = .map
        case .watchlist(let stopId):
            exitFocus()
            watchlistFocusStopId = stopId
            tab = .multistop
        case .trip(let tripId, let vehicleId):
            tab = .map
            focusTrip(tripId, vehicleId: vehicleId)
        case .home:
            tab = .map
        case .tab(let target):
            tab = target
        case .ride:
            tab = .map
            NotificationCenter.default.post(name: .mvkRideCommand, object: WatchRideCommand.start(nil))
        case .disruptions:
            isDisruptionsOpen = true
        }
    }
}

/// One trip to show in the Menetrend: its route, direction and trip.
struct TimetableTripRequest: Equatable {
    let routeId: String
    let dir: String
    let tripId: String
}
