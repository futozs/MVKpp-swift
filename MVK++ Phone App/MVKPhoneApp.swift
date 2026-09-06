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
        }
    }
}
