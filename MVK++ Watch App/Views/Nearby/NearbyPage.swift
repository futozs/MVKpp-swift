//
//  NearbyPage.swift
//  MVK++ Watch App
//

import SwiftUI

/// Közelben: the stops around the rider, closest first, each with its next
/// departures — for the stop you are standing at but never put on the list.
struct NearbyPage: View {
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var catalog: StopsCatalog
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: WatchRouter
    @EnvironmentObject private var link: WatchLink
    @StateObject private var feed = BoardFeed(limit: 2, pollInterval: .seconds(15))

    private static let radiusKm = 1.0
    private static let maxStops = 6

    var body: some View {
        List {
            switch location.status {
            case .denied:
                notice("A helymeghatározás tiltva", "Engedélyezd a Beállítások › Adatvédelem menüben.", icon: "location.slash")
            case .unavailable, .error:
                notice("Nincs helyadat", location.errorMessage ?? "Próbáld újra később.", icon: "location.slash")
            default:
                if location.position == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .frame(width: 20)
                        Text("A helyzetedet keresem…")
                            .font(.footnote)
                    }
                    .listRowBackground(Color.clear)
                } else if nearby.isEmpty {
                    notice("Nincs megálló a közelben", "1 km-en belül egy sincs.", icon: "mappin.slash")
                }
            }

            ForEach(nearby, id: \.stop.id) { item in
                Button {
                    router.push(.stop(item.stop.id))
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(item.stop.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            if let code = StopCode.short(item.stop.id) {
                                StopCodePlate(code: code)
                            }
                            Spacer(minLength: 2)
                            Text(Geo.formatDistance(item.distanceKm))
                                .font(Theme.mono(10, weight: .semibold))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        if let arrivals = feed.results[item.stop.id]?.arrivals {
                            if arrivals.isEmpty {
                                Text("Nincs induló járat")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                            ForEach(arrivals.prefix(2)) { arrival in
                                DepartureRow(arrival: arrival, showsVehicle: false)
                            }
                        }
                    }
                    .glassCard(cornerRadius: 18)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .swipeActions {
                    Button {
                        favorites.toggle(item.stop.id)
                    } label: {
                        Label("Figyelő", systemImage: favorites.contains(item.stop.id) ? "star.slash" : "star")
                    }
                    .tint(Theme.amber400)
                }
            }
        }
        .navigationTitle("Közelben")
        .containerBackground(Theme.early.gradient.opacity(0.3), for: .tabView)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.map)
                } label: {
                    Image(systemName: "map")
                        .foregroundStyle(Theme.primaryForeground)
                }
                .accessibilityLabel("Térkép")
            }
        }
        .onAppear {
            location.start()
            track()
        }
        .onChange(of: nearby.map(\.stop.id)) { _, _ in track() }
        .onChange(of: link.settings.boardKey) { _, _ in track() }
    }

    private struct NearStop {
        let stop: Stop
        let distanceKm: Double
    }

    private var nearby: [NearStop] {
        guard let position = location.position else { return [] }
        return catalog.stops
            .map { NearStop(stop: $0, distanceKm: Geo.distanceKm(position.lat, position.lon, $0.lat, $0.lon)) }
            .filter { $0.distanceKm <= Self.radiusKm }
            .sorted { $0.distanceKm < $1.distanceKm }
            .prefix(Self.maxStops)
            .map { $0 }
    }

    private func track() {
        feed.track(nearby.map(\.stop.id), boardKey: link.settings.boardKey)
    }

    private func notice(_ title: String, _ detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Theme.mutedForeground)
        }
        .listRowBackground(Color.clear)
    }
}
