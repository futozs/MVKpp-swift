//
//  MVK__App.swift
//  MVK++ Watch App
//

import SwiftUI

@main
struct MVK___Watch_AppApp: App {
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var catalog = StopsCatalog()
    @StateObject private var location = LocationProvider()
    @ObservedObject private var router = WatchRouter.shared
    @ObservedObject private var link = WatchLink.shared
    @ObservedObject private var rides = RideController.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(favorites)
                .environmentObject(catalog)
                .environmentObject(location)
                .environmentObject(router)
                .environmentObject(link)
                .environmentObject(rides)
                .tint(Theme.primary)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) { router.open(link) }
                }
                .task {
                    link.activate()
                    location.startIfPermitted()
                    await catalog.loadIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { RealtimeClient.shared.wake() }
                }
        }
    }
}
