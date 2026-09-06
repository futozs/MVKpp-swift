//
//  AddStopSheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// Search the whole stop catalog and toggle stops onto the watchlist. Stays
/// open after each pick, because riders add several at once — home, work, the
/// junction in between.
struct AddStopSheet: View {
    let stops: [Stop]

    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var location: LocationProvider
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(results) { stop in
                let selected = favorites.contains(stop.id)
                let atCapacity = !selected && favorites.stopIds.count >= FavoritesStore.maxCount

                Button {
                    favorites.toggle(stop.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "mappin.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selected ? Theme.primary : Theme.mutedForeground)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.foreground)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(stop.id)
                                    .font(Theme.mono(11, weight: .regular))
                                    .foregroundStyle(Theme.mutedForeground)
                                if let km = distance(to: stop) {
                                    Text(Geo.formatDistance(km))
                                        .font(Theme.mono(11, weight: .regular))
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(atCapacity)
                .opacity(atCapacity ? 0.4 : 1)
                .listRowBackground(selected ? Theme.primary.opacity(0.08) : Color.clear)
                .listRowSeparatorTint(Theme.border)
            }
            .listStyle(.plain)
            .mvkBackground()
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Név vagy megállókód")
            .navigationTitle("Megálló felvétele")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kész") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(favorites.stopIds.isEmpty
                     ? "Még nincs figyelt megálló"
                     : "\(favorites.stopIds.count) / \(FavoritesStore.maxCount) megálló a figyelőn")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
        }
    }

    /// Without a search term, the nearest stops are the useful default — a raw
    /// alphabetical slice of a thousand stops is not a starting point.
    private var results: [Stop] {
        let needle = query.trimmingCharacters(in: .whitespaces)

        if needle.isEmpty {
            guard let position = location.position else { return Array(stops.prefix(60)) }
            return stops
                .sorted {
                    Geo.distanceKm(position.lat, position.lon, $0.lat, $0.lon)
                        < Geo.distanceKm(position.lat, position.lon, $1.lat, $1.lon)
                }
                .prefix(60)
                .map { $0 }
        }

        return stops.filter { $0.matches(needle) }.prefix(80).map { $0 }
    }

    private func distance(to stop: Stop) -> Double? {
        guard let position = location.position else { return nil }
        return Geo.distanceKm(position.lat, position.lon, stop.lat, stop.lon)
    }
}
