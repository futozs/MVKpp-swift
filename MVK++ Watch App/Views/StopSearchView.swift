//
//  StopSearchView.swift
//  MVK++ Watch App
//

import SwiftUI

/// Stop search sheet, presented from the root list's "+" button.
/// Filters the in-memory stop catalog by name or code, diacritic-insensitively.
struct StopSearchView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var catalog: StopsCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredStops: [Stop] {
        catalog.stops.filter { $0.matches(query) }.prefix(20).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List(filteredStops) { stop in
                Button {
                    favorites.add(stop.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.name)
                        Text(stop.code)
                            .font(.caption2)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .disabled(favorites.stopIds.contains(stop.id) || favorites.stopIds.count >= FavoritesStore.maxCount)
                .listRowBackground(Color.clear)
            }
            .mvkBackground()
            .searchable(text: $query, prompt: "Megálló neve")
            .navigationTitle("Megálló hozzáadása")
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
}

#Preview {
    StopSearchView()
        .environmentObject(FavoritesStore())
        .environmentObject(StopsCatalog())
}
