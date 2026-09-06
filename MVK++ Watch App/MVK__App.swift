//
//  MVK__App.swift
//  MVK++ Watch App
//
//

import SwiftUI

@main
struct MVK___Watch_AppApp: App {
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var catalog = StopsCatalog()

    var body: some Scene {
        WindowGroup {
            NextDeparturesListView()
                .environmentObject(favorites)
                .environmentObject(catalog)
                .tint(Theme.primary)
        }
    }
}
