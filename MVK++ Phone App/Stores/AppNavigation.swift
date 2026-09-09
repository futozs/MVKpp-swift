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
        tab = restored?.tab ?? .map
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
        }
    }
}
