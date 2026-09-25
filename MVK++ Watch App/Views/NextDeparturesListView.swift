//
//  NextDeparturesListView.swift
//  MVK++ Watch App
//

import CoreLocation
import SwiftUI
import WatchKit

/// Root view: one row per watched stop, showing its next departure.
/// Polls all watched stops in a single batched request every 4s, plus an
/// immediate refresh whenever the app comes back to the foreground (so
/// waking the watch doesn't leave stale data sitting until the next tick).
/// When "nearest first" is on (toggled from the phone app), reorders by
/// GPS distance to each stop.
struct NextDeparturesListView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var catalog: StopsCatalog
    @StateObject private var viewModel = NextDeparturesViewModel()
    @StateObject private var location = LocationProvider()
    @StateObject private var coordinator = NavigationCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAddEntry = false
    @State private var showingLookupEntry = false
    /// Set by the lookup keypad, consumed once its sheet is fully gone —
    /// pushing while the sheet is still on screen drops the navigation.
    @State private var pendingLookupStopId: String?
    /// Stop the user long-pressed, awaiting delete confirmation.
    @State private var pendingDeleteStopId: String?

    private static let pollInterval: Duration = .seconds(4)

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            content
                .background(AppBackground())
                .navigationDestination(for: String.self) { stopId in
                    StopDetailView(stopId: stopId)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingLookupEntry = true
                        } label: {
                            Image(systemName: "square.grid.3x3.fill")
                                .foregroundStyle(.white)
                        }
                        .tint(Theme.card)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingAddEntry = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.white)
                        }
                        .tint(Theme.card)
                    }
                }
                .sheet(isPresented: $showingLookupEntry, onDismiss: openPendingLookup) {
                    StopCodeEntryView(mode: .lookup) { pendingLookupStopId = $0 }
                        .environmentObject(favorites)
                        .environmentObject(catalog)
                }
                .modifier(DeleteConfirmation(stopId: $pendingDeleteStopId, name: deleteTargetName, onConfirm: favorites.remove))
                .sheet(isPresented: $showingAddEntry) {
                    StopCodeEntryView(mode: .add)
                        .environmentObject(favorites)
                        .environmentObject(catalog)
                }
                .task(id: favorites.stopIds) {
                    await pollLoop()
                }
                .onChange(of: needsLocation, initial: true) { _, enabled in
                    if enabled {
                        location.start()
                    } else {
                        location.stop()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await viewModel.refresh(stopIds: favorites.stopIds) }
                    }
                }
        }
        .environmentObject(coordinator)
    }

    @ViewBuilder
    private var content: some View {
        if favorites.stopIds.isEmpty {
            ContentUnavailableView(
                "Nincs figyelt megálló",
                systemImage: "bus.doubledecker",
                description: Text("Adj hozzá egyet a + gombbal")
            )
        } else {
            List {
                ForEach(orderedStopIds, id: \.self, content: stopRow)
                    .onDelete { offsets in
                        offsets.map { orderedStopIds[$0] }.forEach(favorites.remove)
                    }
            }
            .mvkBackground()
        }
    }

    /// Tap opens the stop, long press offers to drop it from the watched
    /// list — watchOS routes a long press straight through NavigationLink
    /// and `contextMenu`, so the row owns both gestures itself.
    private func stopRow(_ stopId: String) -> some View {
        StopRowView(
            stopId: stopId,
            result: viewModel.results[stopId],
            isLoading: viewModel.isLoading
        )
        .contentShape(Rectangle())
        // Long press is attached first so the tap sits outside it and wins a
        // short touch; the guard covers the case where both still fire.
        .onLongPressGesture(minimumDuration: 0.45) {
            WKInterfaceDevice.current().play(.click)
            pendingDeleteStopId = stopId
        }
        .onTapGesture {
            guard pendingDeleteStopId == nil else { return }
            coordinator.path.append(stopId)
        }
        .listRowBackground(Color.clear)
    }

    private var deleteTargetName: String {
        guard let stopId = pendingDeleteStopId else { return "" }
        return viewModel.results[stopId]?.stop.name ?? stopId
    }

    /// Navigates to the stop the lookup keypad resolved, now that its sheet
    /// has finished dismissing.
    private func openPendingLookup() {
        guard let stopId = pendingLookupStopId else { return }
        pendingLookupStopId = nil
        coordinator.path.append(stopId)
    }

    /// Either the list is sorted by distance, or the widget follows the
    /// nearest watched stop — which needs the permission granted here, in
    /// the app, before the widget extension can get a fix of its own.
    private var needsLocation: Bool {
        favorites.nearestFirstEnabled || favorites.widgetNearestEnabled
    }

    private var orderedStopIds: [String] {
        guard favorites.nearestFirstEnabled, let userCoordinate = location.coordinate else {
            return favorites.stopIds
        }
        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        return favorites.stopIds.sorted {
            distance(to: $0, from: userLocation) < distance(to: $1, from: userLocation)
        }
    }

    private func distance(to stopId: String, from userLocation: CLLocation) -> CLLocationDistance {
        guard let stop = viewModel.results[stopId]?.stop,
              let lat = stop.lat, let lon = stop.lon else {
            return .greatestFiniteMagnitude
        }
        return userLocation.distance(from: CLLocation(latitude: lat, longitude: lon))
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await viewModel.refresh(stopIds: favorites.stopIds)
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}

/// Confirmation sheet for a long-press delete, kept out of the root body so
/// the type-checker isn't asked to solve one giant expression.
private struct DeleteConfirmation: ViewModifier {
    @Binding var stopId: String?
    let name: String
    let onConfirm: (String) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Megálló törlése",
            isPresented: Binding(
                get: { stopId != nil },
                set: { if !$0 { stopId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Törlés", role: .destructive) {
                if let stopId { onConfirm(stopId) }
            }
            Button("Mégse", role: .cancel) {}
        } message: {
            Text(name)
        }
    }
}

#Preview {
    NextDeparturesListView()
        .environmentObject(FavoritesStore())
        .environmentObject(StopsCatalog())
}
