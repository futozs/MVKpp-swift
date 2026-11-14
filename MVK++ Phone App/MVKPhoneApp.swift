//
//  MVKPhoneApp.swift
//  MVK++ Phone App
//

import SwiftUI

@main
struct MVKPhoneApp: App {
    @StateObject private var store = TransitStore()
    @StateObject private var navigation = AppNavigation()
    @StateObject private var location = LocationProvider()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var lineFavorites = LineFavoritesStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(navigation)
                .environmentObject(location)
                .environmentObject(favorites)
                .environmentObject(lineFavorites)
                .tint(Theme.primary)
                .preferredColorScheme(.dark)
                .task { await NotificationCenterStore.shared.configure() }
                .task { RideController.shared.attach(location: location, transit: store) }
                .onOpenURL { url in
                    guard let link = DeepLink(url: url) else { return }
                    // The Megállófigyelő only has a card for a stop it is
                    // watching, so a link that lands there has to put it on
                    // the list first. Already-watched stops are left alone,
                    // and a full list simply keeps what it has.
                    if case .watchlist(let stopId) = link, !favorites.contains(stopId) {
                        favorites.add(stopId)
                    }
                    navigation.open(link)
                }
        }
    }
}
