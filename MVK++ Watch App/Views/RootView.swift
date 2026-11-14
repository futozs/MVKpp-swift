//
//  RootView.swift
//  MVK++ Watch App
//

import SwiftUI

/// Three vertical pages — Figyelő, Közelben, Továbbiak — under one
/// navigation stack, so any page can push any screen.
struct RootView: View {
    @EnvironmentObject private var router: WatchRouter

    var body: some View {
        NavigationStack(path: $router.path) {
            TabView(selection: $router.page) {
                WatchlistPage()
                    .tag(WatchPage.watchlist)
                NearbyPage()
                    .tag(WatchPage.nearby)
                MorePage()
                    .tag(WatchPage.more)
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: WatchRoute.self, destination: destination)
        }
    }

    @ViewBuilder
    private func destination(_ route: WatchRoute) -> some View {
        switch route {
        case .stop(let stopId):
            StopDetailView(stopId: stopId)
        case .trip(let trip):
            TripFollowView(trip: trip)
        case .ride:
            RideView()
        case .boardPicker:
            BoardPickerView()
        case .boardDestination(let trip):
            BoardDestinationView(trip: trip)
        case .map:
            WatchMapView()
        case .timetable:
            TimetableRoutesView()
        case .timetableRoute(let route):
            TimetableDirectionsView(route: route)
        case .timetableStops(let routeId, let dir):
            TimetableStopsView(routeId: routeId, dir: dir)
        case .disruptions:
            DisruptionsView()
        case .news:
            NewsListView()
        case .newsItem(let item):
            NewsDetailView(item: item)
        case .settings:
            WatchSettingsView()
        case .search:
            StopSearchView()
        }
    }
}
