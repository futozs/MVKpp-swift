//
//  MultiStopScreen.swift
//  MVK++ Phone App
//

import SwiftUI

/// The watchlist. Several stops the rider cares about, each showing its next
/// departure, swipeable one card at a time.
///
/// The default ordering is by distance: standing at a stop, the card you want
/// is the one for where you are, and the app can work that out.
struct MultiStopScreen: View {

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var favorites: FavoritesStore

    @State private var isPickerOpen = false
    @State private var isReordering = false
    @State private var page = 0

    /// Junctions worth offering to someone with an empty list — every MVK
    /// route touches at least one of them.
    private let quickStops = [
        ("Tiszai pályaudvar", "Tiszai"),
        ("Búza tér", "Búza"),
        ("Villanyrendőr", "Villany"),
        ("Újgyőri főtér", "Újgyőri"),
        ("Avas kilátó", "Avas kilátó"),
        ("Miskolctapolca, Barlangfürdő", "Tapolca"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if watchedStops.isEmpty {
                    emptyState
                } else {
                    carousel
                }
            }
            .background(AppBackground())
            .navigationTitle("Megállófigyelő")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $isPickerOpen) {
                AddStopSheet(stops: store.stops)
                    .presentationDetents([.large])
            }
            .onChange(of: nearestId) { _, id in
                // A newly closest stop is the one to be looking at.
                guard id != nil, !isReordering else { return }
                withAnimation(Theme.Motion.normalAnimation) { page = 0 }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if watchedStops.count > 1, location.position != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    favorites.nearestFirstEnabled.toggle()
                } label: {
                    Image(systemName: favorites.nearestFirstEnabled
                          ? "location.fill"
                          : "location")
                }
                .tint(favorites.nearestFirstEnabled ? Theme.primary : Theme.mutedForeground)
                .accessibilityLabel("Legközelebbi megálló elöl")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPickerOpen = true
            } label: {
                Label("Megálló felvétele", systemImage: "plus")
            }
        }
    }

    // MARK: - Carousel

    private var carousel: some View {
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(watchedStops.enumerated()), id: \.element.id) { index, stop in
                    StopCardView(
                        stop: stop,
                        distanceKm: distances[stop.id],
                        isNearest: stop.id == nearestId,
                        onRemove: { favorites.remove($0) },
                        onFocusMap: { stop, tripId, vehicleId in
                            navigation.focusStopOnMap(stop, tripId: tripId, vehicleId: vehicleId)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if watchedStops.count > 1 { pageIndicator }
        }
        .padding(.top, 8)
    }

    private var pageIndicator: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(Theme.Motion.normalAnimation) { page = max(0, page - 1) }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.glass)
            .disabled(page <= 0)
            .accessibilityLabel("Előző megálló")

            Spacer(minLength: 8)

            if watchedStops.count <= 8 {
                HStack(spacing: 6) {
                    ForEach(watchedStops.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.primary : Theme.mutedForeground.opacity(0.35))
                            .frame(width: index == page ? 22 : 8, height: 8)
                            .animation(Theme.Motion.fastAnimation, value: page)
                            .onTapGesture {
                                withAnimation(Theme.Motion.normalAnimation) { page = index }
                            }
                    }
                }
                .accessibilityHidden(true)
            } else {
                Text("\(page + 1) / \(watchedStops.count)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.mutedForeground)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(Theme.Motion.normalAnimation) {
                    page = min(watchedStops.count - 1, page + 1)
                }
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.glass)
            .disabled(page >= watchedStops.count - 1)
            .accessibilityLabel("Következő megálló")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 56, height: 56)
                    .background(
                        Theme.primary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                    )

                Text("A figyelő üres")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 16)

                Button {
                    isPickerOpen = true
                } label: {
                    Label("Megállók böngészése", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.primary)
                .padding(.top, 20)

                Divider()
                    .overlay(Theme.border)
                    .padding(.vertical, 28)

                Text("GYAKORI CSOMÓPONTOK")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.mutedForeground)

                FlowLayout(spacing: 8, alignment: .center) {
                    ForEach(quickStops, id: \.0) { label, needle in
                        Button(label) { addByName(needle) }
                            .font(.system(size: 13, weight: .medium))
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.md))
                            .tint(Theme.primary)
                    }
                }
                .padding(.top, 12)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .dataCard()
            .padding(16)
        }
    }

    // MARK: - Derived data

    private var manualOrder: [Stop] {
        favorites.stopIds.compactMap { store.stop(id: $0) }
    }

    private var distances: [String: Double] {
        guard let position = location.position else { return [:] }
        return manualOrder.reduce(into: [:]) { result, stop in
            result[stop.id] = Geo.distanceKm(position.lat, position.lon, stop.lat, stop.lon)
        }
    }

    private var sortsByDistance: Bool {
        favorites.nearestFirstEnabled && !isReordering && !distances.isEmpty
    }

    private var watchedStops: [Stop] {
        guard sortsByDistance else { return manualOrder }
        return manualOrder.sorted { (distances[$0.id] ?? .infinity) < (distances[$1.id] ?? .infinity) }
    }

    private var nearestId: String? {
        sortsByDistance ? watchedStops.first?.id : nil
    }

    private func addByName(_ needle: String) {
        guard let found = store.stops.first(where: { $0.matches(needle) }) else { return }
        favorites.toggle(found.id)
    }
}
