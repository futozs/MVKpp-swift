//
//  StopSearchView.swift
//  MVK++ Watch App
//

import SwiftUI

/// Stop search by name or number, diacritic-insensitively. A pick opens the
/// stop; its star puts it on the Figyelő.
struct StopSearchView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var catalog: StopsCatalog
    @EnvironmentObject private var router: WatchRouter
    @State private var query = ""

    private var filteredStops: [Stop] {
        catalog.stops.filter { $0.matches(query) }.prefix(20).map { $0 }
    }

    var body: some View {
        List(filteredStops) { stop in
            Button {
                router.push(.stop(stop.id))
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.name)
                            .font(.footnote.weight(.semibold))
                        if let code = StopCode.short(stop.id) {
                            StopCodePlate(code: code)
                        }
                    }
                    Spacer(minLength: 2)
                    if favorites.contains(stop.id) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.amber400)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Megálló neve vagy száma")
        .navigationTitle("Keresés")
        .overlay {
            if catalog.isLoading && catalog.stops.isEmpty {
                ProgressView()
            } else if query.isEmpty {
                ContentUnavailableView("Keress megállóra", systemImage: "magnifyingglass")
            } else if filteredStops.isEmpty {
                ContentUnavailableView.search
            }
        }
        .task {
            await catalog.loadIfNeeded()
        }
    }
}
