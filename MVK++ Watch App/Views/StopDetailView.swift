//
//  StopDetailView.swift
//  MVK++ Watch App
//

import SwiftUI

/// One stop's full board, live. A tap follows the run on the map; a swipe
/// says "Felszálltam". The star puts the stop on the Figyelő list.
struct StopDetailView: View {
    let stopId: String
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var catalog: StopsCatalog
    @EnvironmentObject private var router: WatchRouter
    @EnvironmentObject private var link: WatchLink
    @StateObject private var feed = BoardFeed(limit: 12, pollInterval: .seconds(5))

    private var response: StopArrivalsResponse? { feed.results[stopId] }

    var body: some View {
        List {
            header
                .listRowBackground(Color.clear)

            if let response {
                if response.arrivals.isEmpty {
                    Text("Innen ma már nem indul járat.")
                        .font(.footnote)
                        .foregroundStyle(Theme.mutedForeground)
                        .listRowBackground(Color.clear)
                }
                ForEach(Array(response.arrivals.enumerated()), id: \.element.id) { index, arrival in
                    Button {
                        router.push(.trip(trip(arrival)))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            DepartureRow(arrival: arrival, showsVehicle: link.settings.predictedVehicle || arrival.vehicle != nil)
                            if index == 0 { ApproachLine(arrival: arrival) }
                        }
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.card.opacity(0.75))
                    )
                    .swipeActions(edge: .leading) {
                        Button {
                            router.push(.boardDestination(trip(arrival)))
                        } label: {
                            Label("Felszálltam", systemImage: "ticket")
                        }
                        .tint(Theme.primary)
                    }
                }
                if let rtError = response.rtError {
                    Text(rtError)
                        .font(.caption2)
                        .foregroundStyle(Theme.late)
                        .listRowBackground(Color.clear)
                }
            } else if let error = feed.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.late)
                    .listRowBackground(Color.clear)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(StopCode.short(stopId) ?? "Megálló")
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(Theme.primary.gradient.opacity(0.25), for: .navigation)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(stopId)
                } label: {
                    Image(systemName: favorites.contains(stopId) ? "star.fill" : "star")
                        .foregroundStyle(Theme.primaryForeground)
                }
                .accessibilityLabel(favorites.contains(stopId) ? "Levétel a Figyelőről" : "Felvétel a Figyelőre")
            }
        }
        .refreshable { await feed.refresh() }
        .onAppear { feed.track([stopId], boardKey: link.settings.boardKey) }
        .onDisappear { feed.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(2)
            if let updated = feed.updatedAt {
                HStack(spacing: 4) {
                    Circle()
                        .fill(RealtimeClient.shared.connected ? Theme.live : Theme.offline)
                        .frame(width: 6, height: 6)
                    Text(updated, style: .time)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.mutedForeground)
            }
        }
    }

    private var name: String {
        response?.stop.name ?? catalog.stops.first { $0.id == stopId }?.name ?? stopId
    }

    private func trip(_ arrival: ArrivalItem) -> TripRef {
        TripRef(arrival: arrival, stopId: stopId, stopName: response?.stop.name)
    }
}
