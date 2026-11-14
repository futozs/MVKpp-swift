//
//  BoardViews.swift
//  MVK++ Watch App
//

import SwiftUI
import WatchKit

/// "Felszálltam" without a run picked: the buses leaving the nearest stops
/// right now. The one the rider is on is almost always at the top.
struct BoardPickerView: View {
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var catalog: StopsCatalog
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var router: WatchRouter
    @EnvironmentObject private var link: WatchLink
    @StateObject private var feed = BoardFeed(limit: 6, pollInterval: .seconds(10))

    var body: some View {
        List {
            if stops.isEmpty {
                Text(location.position == nil ? "A helyzetedet keresem…" : "Nincs megálló a közelben.")
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedForeground)
                    .listRowBackground(Color.clear)
            }
            ForEach(stops, id: \.stop.id) { item in
                if let arrivals = feed.results[item.stop.id]?.arrivals.filter({ $0.etaMin <= 5 && !$0.isCancelled }), !arrivals.isEmpty {
                    Section {
                        ForEach(arrivals) { arrival in
                            Button {
                                router.push(.boardDestination(TripRef(arrival: arrival, stopId: item.stop.id, stopName: item.stop.name)))
                            } label: {
                                DepartureRow(arrival: arrival)
                            }
                        }
                    } header: {
                        Text("\(item.stop.name) · \(Geo.formatDistance(item.distanceKm))")
                            .lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("Felszálltam")
        .onAppear {
            location.start()
            track()
        }
        .onChange(of: stops.map(\.stop.id)) { _, _ in track() }
        .onDisappear { feed.stop() }
    }

    private struct NearStop {
        let stop: Stop
        let distanceKm: Double
    }

    /// The three closest stops; without a fix, the watchlist.
    private var stops: [NearStop] {
        guard let position = location.position else {
            return favorites.stopIds.prefix(3).compactMap { id in
                catalog.stops.first { $0.id == id }.map { NearStop(stop: $0, distanceKm: 0) }
            }
        }
        return catalog.stops
            .map { NearStop(stop: $0, distanceKm: Geo.distanceKm(position.lat, position.lon, $0.lat, $0.lon)) }
            .filter { $0.distanceKm < 0.6 }
            .sorted { $0.distanceKm < $1.distanceKm }
            .prefix(3)
            .map { $0 }
    }

    private func track() {
        feed.track(stops.map(\.stop.id), boardKey: link.settings.boardKey)
    }
}

/// "Hol szállsz le?" — the run's remaining stops after the one the rider got
/// on at. Skipping it rides to the terminus.
struct BoardDestinationView: View {
    let trip: TripRef
    @EnvironmentObject private var rides: RideController
    @EnvironmentObject private var router: WatchRouter
    @State private var stops: [TripProgressStop] = []
    @State private var failed = false

    var body: some View {
        List {
            Section {
                Button {
                    start(destination: nil)
                } label: {
                    Label("Végállomásig", systemImage: "flag.checkered")
                }
                .disabled(rides.isStarting)
            }

            Section("Hol szállsz le?") {
                if stops.isEmpty {
                    if failed {
                        Text("Ennek a menetnek a megállói nem érhetők el.")
                            .font(.caption2)
                            .foregroundStyle(Theme.mutedForeground)
                    } else {
                        ProgressView()
                    }
                }
                ForEach(remaining) { stop in
                    Button {
                        start(destination: stop)
                    } label: {
                        Text(stop.name)
                            .font(.footnote)
                    }
                    .disabled(rides.isStarting)
                }
            }
        }
        .navigationTitle(trip.route.isEmpty ? "Felszálltam" : trip.route)
        .overlay {
            if rides.isStarting { ProgressView() }
        }
        .task(id: trip.tripId) {
            do {
                stops = try await APIClient.shared.tripProgress(tripId: trip.tripId, vehicleId: trip.vehicleId).stops
            } catch {
                failed = true
            }
        }
    }

    /// Stops after the boarding one; the whole run when it is not known.
    private var remaining: [TripProgressStop] {
        guard let boardId = trip.stopId, let index = stops.firstIndex(where: { $0.id == boardId }) else {
            return stops
        }
        return Array(stops.dropFirst(index + 1))
    }

    private func start(destination: TripProgressStop?) {
        let request = WatchRideRequest(
            tripId: trip.tripId,
            vehicleId: trip.vehicleId,
            route: trip.route,
            color: trip.color,
            textColor: trip.textColor,
            headsign: trip.headsign,
            boardStopId: trip.stopId,
            boardStopName: trip.stopName,
            destinationStopId: destination?.id,
            destinationStopName: destination?.name
        )
        Task {
            await rides.board(request)
            WKInterfaceDevice.current().play(.success)
            router.show(.ride)
        }
    }
}
