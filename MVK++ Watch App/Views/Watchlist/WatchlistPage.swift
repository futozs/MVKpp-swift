//
//  WatchlistPage.swift
//  MVK++ Watch App
//

import CoreLocation
import SwiftUI
import WatchKit

/// Figyelő: the rider's watched stops — the same list as the phone and the
/// web (`mvk_monitored_stops`) — each with its next departures, live.
/// "Legközelebbi elöl" sorts by distance and outlines the closest one.
struct WatchlistPage: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var catalog: StopsCatalog
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var router: WatchRouter
    @EnvironmentObject private var link: WatchLink
    @StateObject private var feed = BoardFeed(limit: 3, reloadsWidgets: true)
    @State private var showingLookup = false
    @State private var showingAdd = false
    @State private var pendingLookupStopId: String?

    var body: some View {
        content
            .navigationTitle("Figyelő")
            .containerBackground(Theme.primary.gradient.opacity(0.35), for: .tabView)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingLookup = true
                    } label: {
                        Image(systemName: "square.grid.3x3.fill")
                            .foregroundStyle(Theme.primaryForeground)
                    }
                    .accessibilityLabel("Megálló kódja")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.primaryForeground)
                    }
                    .accessibilityLabel("Megálló felvétele")
                }
            }
            .sheet(isPresented: $showingLookup, onDismiss: openPendingLookup) {
                StopCodeEntryView(mode: .lookup) { pendingLookupStopId = $0 }
                    .environmentObject(favorites)
                    .environmentObject(catalog)
            }
            .sheet(isPresented: $showingAdd) {
                StopCodeEntryView(mode: .add)
                    .environmentObject(favorites)
                    .environmentObject(catalog)
            }
            .onAppear { feed.track(favorites.stopIds, boardKey: link.settings.boardKey) }
            .onChange(of: favorites.stopIds) { _, ids in feed.track(ids, boardKey: link.settings.boardKey) }
            .onChange(of: link.settings.boardKey) { _, key in feed.track(favorites.stopIds, boardKey: key) }
            .onChange(of: favorites.nearestFirstEnabled) { _, on in if on { location.start() } }
    }

    @ViewBuilder
    private var content: some View {
        List {
            if let ride = link.ride {
                RideBanner(ride: ride)
                    .listRowBackground(Color.clear)
            }

            if favorites.stopIds.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                ForEach(orderedStopIds, id: \.self) { stopId in
                    Button {
                        router.push(.stop(stopId))
                    } label: {
                        WatchlistCard(
                            stopId: stopId,
                            name: name(of: stopId),
                            result: feed.results[stopId],
                            distanceKm: distanceKm(to: stopId),
                            isNearest: favorites.nearestFirstEnabled && stopId == nearestStopId,
                            isLoading: feed.isLoading
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(role: .destructive) {
                            favorites.remove(stopId)
                        } label: {
                            Label("Törlés", systemImage: "trash")
                        }
                    }
                }
            }

            if let error = feed.errorMessage, feed.results.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.late)
                    .listRowBackground(Color.clear)
            }

            Button {
                router.push(.search)
            } label: {
                Label("Keresés név szerint", systemImage: "magnifyingglass")
                    .font(.footnote)
            }
            .listRowBackground(Color.clear)
        }
        .refreshable { await feed.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bus.doubledecker")
                .font(.title2)
                .foregroundStyle(Theme.primary)
            Text("Nincs figyelt megálló")
                .font(.headline)
            Text("Vedd fel a + gombbal, vagy a telefonon — itt is megjelenik.")
                .font(.caption2)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func openPendingLookup() {
        guard let stopId = pendingLookupStopId else { return }
        pendingLookupStopId = nil
        router.push(.stop(stopId))
    }

    // MARK: - Order

    private var orderedStopIds: [String] {
        guard favorites.nearestFirstEnabled, location.position != nil else { return favorites.stopIds }
        return favorites.stopIds.sorted {
            (distanceKm(to: $0) ?? .greatestFiniteMagnitude) < (distanceKm(to: $1) ?? .greatestFiniteMagnitude)
        }
    }

    private var nearestStopId: String? {
        guard location.position != nil else { return nil }
        return favorites.stopIds.min {
            (distanceKm(to: $0) ?? .greatestFiniteMagnitude) < (distanceKm(to: $1) ?? .greatestFiniteMagnitude)
        }
    }

    private func coordinate(of stopId: String) -> (Double, Double)? {
        if let stop = feed.results[stopId]?.stop, let lat = stop.lat, let lon = stop.lon { return (lat, lon) }
        if let stop = catalog.stops.first(where: { $0.id == stopId }) { return (stop.lat, stop.lon) }
        return nil
    }

    private func distanceKm(to stopId: String) -> Double? {
        guard let position = location.position, let (lat, lon) = coordinate(of: stopId) else { return nil }
        return Geo.distanceKm(position.lat, position.lon, lat, lon)
    }

    private func name(of stopId: String) -> String {
        feed.results[stopId]?.stop.name
            ?? catalog.stops.first { $0.id == stopId }?.name
            ?? stopId
    }
}

/// One watched stop: its name and plate, then the next bus large and the
/// two after it in a line each.
struct WatchlistCard: View {
    let stopId: String
    let name: String
    let result: StopArrivalsResponse?
    let distanceKm: Double?
    var isNearest = false
    var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if let first = result?.arrivals.first {
                hero(first)
                ForEach(result?.arrivals.dropFirst().prefix(2) ?? [], id: \.id) { arrival in
                    DepartureRow(arrival: arrival, showsVehicle: false)
                }
            } else if result != nil {
                Text("Nincs induló járat")
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedForeground)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Nincs adat")
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .glassCard(cornerRadius: 18)
        .overlay {
            if isNearest {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.primary, lineWidth: 2)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(2)
            if let code = StopCode.short(stopId) {
                StopCodePlate(code: code)
            }
            Spacer(minLength: 2)
            if let distanceKm {
                Text(Geo.formatDistance(distanceKm))
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(isNearest ? Theme.primary : Theme.mutedForeground)
            }
        }
    }

    private func hero(_ arrival: ArrivalItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                RouteTile(short: arrival.route, colorHex: arrival.color, textHex: arrival.text, size: .large)
                    .opacity(arrival.isCancelled ? 0.45 : 1)
                Spacer(minLength: 2)
                CountdownView(etaMin: arrival.etaMin, style: .hero)
            }
            Text(arrival.headsign)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .strikethrough(arrival.isCancelled)
            Group {
                if arrival.isCancelled {
                    Text("Kimarad").foregroundStyle(Theme.destructive)
                } else {
                    DelayText(arrival: arrival)
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            ApproachLine(arrival: arrival)
        }
    }
}
