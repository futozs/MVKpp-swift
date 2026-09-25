//
//  MapScreen.swift
//  MVK++ Phone App
//

import CoreLocation
import Combine
import SwiftUI

/// The live network map. Everything that floats over the tiles is Liquid
/// Glass; the map itself is the content layer underneath, which is exactly the
/// hierarchy glass is meant to express.
struct MapScreen: View {

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var favorites: FavoritesStore

    @StateObject private var camera = MapCameraController()
    @StateObject private var tripPath = TripPathModel()
    @StateObject private var shapes = RouteShapeCache()

    @State private var isPanelOpen = false
    @State private var isBaseMapOpen = false
    @State private var isCodeSearchOpen = false
    @State private var tappedVehicle: VehicleAnnotation?

    /// The first fix should recentre the map; later ones must not yank it out
    /// from under the rider.
    @State private var autoZoom: AutoZoomStage = .pending
    @State private var lastWatchKey = ""
    @State private var didCenterOnFocus = false
    /// Stays true until the rider pans or zooms; once they take the wheel the
    /// map stops chasing the vehicle.
    @State private var mapFollowsVehicle = true

    private enum AutoZoomStage { case pending, usedStaleFix, done }

    private let nearStopKm = 0.4
    private let closeZoom: Double = 17
    private let meZoom: Double = 16

    var body: some View {
        ZStack {
            map
            overlays
            if isCodeSearchOpen { codeSearch }
        }
        // While a vehicle is locked on, the tab bar goes away: the focus card
        // is the whole interface, and the map gets the rest of the screen.
        .toolbar(navigation.isFollowingTrip ? .hidden : .visible, for: .tabBar)
        .animation(Theme.Motion.normalAnimation, value: navigation.isFollowingTrip)
        .sheet(isPresented: $isPanelOpen) { controlPanel }
        .sheet(isPresented: $isBaseMapOpen) {
            MapSettingsSheet(selectedLayerId: $navigation.tileLayerId)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: selectedStopBinding) { stop in
            StopDetailSheet(
                stop: stop,
                isMonitored: favorites.contains(stop.id),
                onToggleMonitor: favorites.toggle,
                onFocusTrip: { tripId, vehicleId in
                    navigation.focusTrip(tripId, vehicleId: vehicleId)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .task(id: navigation.filters.routes) {
            await shapes.load(routeIds: navigation.filters.routes)
        }
        .onChange(of: navigation.focusTripId) { _, tripId in
            didCenterOnFocus = false
            mapFollowsVehicle = true
            tappedVehicle = nil
            tripPath.follow(tripId: tripId, vehicleId: navigation.focusVehicleId)
            store.startPolling(paused: tripId != nil)
        }
        .onChange(of: tripPath.path?.vehicle?.id) { _, _ in centreOnFollowedVehicle() }
        .onChange(of: tripPath.path?.vehicle?.lat) { _, _ in centreOnFollowedVehicle() }
        .onChange(of: navigation.selectedStopId) { _, stopId in
            guard let stop = store.stop(id: stopId) else { return }
            camera.send(.flyAtLeast(
                CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon),
                minZoom: closeZoom
            ))
        }
        .onChange(of: location.position) { _, _ in runAutoZoom() }
        .onChange(of: store.liveVehicles) { _, _ in frameWatchedVehicles() }
        .onAppear {
            tripPath.follow(tripId: navigation.focusTripId, vehicleId: navigation.focusVehicleId)
            store.startPolling(paused: navigation.isFollowingTrip)
        }
    }

    // MARK: - Map

    private var map: some View {
        TransitMapRepresentable(
            stops: store.stops,
            routes: store.routes,
            vehicles: store.liveVehicles,
            filters: navigation.filters,
            tileLayer: navigation.tileLayer,
            selectedStopId: navigation.selectedStopId,
            monitoredStopIds: favorites.stopIds,
            focusTripId: navigation.focusTripId,
            focusPath: tripPath.path,
            routeShapes: shapes.shapes,
            showsUserLocation: location.position != nil,
            camera: camera,
            onSelectStop: { navigation.selectedStopId = $0 },
            onSelectVehicle: { annotation in
                tappedVehicle = annotation
                // Zoom to the bus the rider just tapped — the card below then
                // offers to lock on to it.
                camera.send(.flyAtLeast(annotation.coordinate, minZoom: 16))
            },
            onUserMovedMap: { mapFollowsVehicle = false },
            userPosition: location.position
        )
        .ignoresSafeArea()
    }

    // MARK: - Floating controls

    private var overlays: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 12)
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.top, 8)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 8) {
            if !navigation.isFollowingTrip {
                Button {
                    isPanelOpen = true
                } label: {
                    Label("Szűrés", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        // White, not the brand green: this label sits over
                        // live map tiles, and green on green is unreadable.
                        .foregroundStyle(.white)
                }
                .buttonStyle(.glass)
                .tint(.white)
            }

            Spacer(minLength: 8)

            if navigation.filters.isActive && !navigation.isFollowingTrip {
                Button {
                    navigation.clearFilters()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "scope").font(.system(size: 12))
                        Text(filterSummary)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .floatingGlass(tint: Theme.primary.opacity(0.35))
                .frame(maxWidth: 240, alignment: .trailing)
                .accessibilityLabel("\(filterSummary) — szűrők törlése")
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            // Locked on to a vehicle: the card is the only chrome. Everything
            // else — controls, tab bar — steps aside.
            if navigation.isFollowingTrip, let tripId = navigation.focusTripId {
                VehicleFocusCard(
                    tripId: tripId,
                    vehicleId: navigation.focusVehicleId,
                    stops: store.stops,
                    model: tripPath,
                    onClose: { navigation.exitFocus() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(alignment: .bottom) {
                    GlassCircleButton {
                        isCodeSearchOpen = true
                    } label: {
                        Image(systemName: "number")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Ugrás megállókód alapján")

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        if let message = location.errorMessage, location.status != .idle {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.trailing)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .floatingGlass()
                                .frame(maxWidth: 220)
                        }

                        GlassCircleButton(
                            tint: location.isActive ? Theme.primary.opacity(0.3) : nil,
                            action: handleLocate
                        ) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(location.isActive ? Theme.primary : .white)
                                .symbolEffect(.pulse, isActive: location.status == .requesting)
                        }
                        .disabled(location.status == .requesting)
                        .accessibilityLabel(location.position == nil ? "Helymeghatározás bekapcsolása" : "Ugrás a helyzetemre")
                    }
                }

                if let tappedVehicle {
                    VehiclePreviewCard(
                        annotation: tappedVehicle,
                        onFollow: {
                            navigation.focusTrip(tappedVehicle.tripId, vehicleId: tappedVehicle.vehicleId)
                        },
                        onClose: { self.tappedVehicle = nil }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 12)
        .animation(Theme.Motion.normalAnimation, value: navigation.focusTripId)
        .animation(Theme.Motion.normalAnimation, value: tappedVehicle?.vehicleId)
        .padding(.bottom, 8)
    }

    private var controlPanel: some View {
        MapControlPanel(
            routes: store.routes,
            vehicles: store.liveVehicles,
            stops: store.stops,
            visibleVehicles: filteredVehicles,
            monitoredStopIds: favorites.stopIds,
            selectedStopId: navigation.selectedStopId,
            filters: $navigation.filters,
            onOpenBaseMap: {
                isPanelOpen = false
                isBaseMapOpen = true
            },
            onFlyToVehicle: { vehicle in
                guard let coordinate = vehicle.coordinate else { return }
                camera.send(.fly(coordinate, zoom: 16))
                tappedVehicle = VehicleAnnotation(vehicle: vehicle, tracked: false, showLabel: true)
            },
            onSelectStop: { navigation.selectedStopId = $0.id },
            onFlyTo: { camera.send(.fly($0, zoom: 16)) },
            onToggleMonitorStop: favorites.toggle
        )
    }

    // MARK: - Stop code search
    //
    // The number printed on the stop sign is the only identifier riders
    // actually carry, so it gets a dedicated keypad rather than being buried
    // in the stop list's text search.

    private var codeSearch: some View {
        StopCodeSearchOverlay(
            stops: store.stops,
            onClose: { isCodeSearchOpen = false },
            onResolved: { stopId, coordinate in
                if let coordinate { camera.send(.fly(coordinate, zoom: closeZoom)) }
                navigation.selectedStopId = stopId
                isCodeSearchOpen = false
            }
        )
    }

    // MARK: - Camera behaviour

    private func handleLocate() {
        guard location.position != nil else {
            location.start()
            return
        }
        focusOnMe(animated: true)
    }

    /// Frames the rider together with their nearest stop when one is within
    /// walking distance — that pairing is the useful view, not the rider alone
    /// floating in the middle of the screen.
    private func focusOnMe(animated: Bool) {
        guard let position = location.position else { return }
        let me = position.coordinate

        if let hit = Geo.nearest(store.stops, lat: position.lat, lon: position.lon), hit.km <= nearStopKm {
            let stop = CLLocationCoordinate2D(latitude: hit.item.lat, longitude: hit.item.lon)
            camera.send(.fit([me, stop], maxZoom: closeZoom))
            return
        }

        camera.send(animated ? .fly(me, zoom: meZoom) : .jump(me, zoom: meZoom))
    }

    private func runAutoZoom() {
        guard autoZoom != .done, location.position != nil, !store.stops.isEmpty else { return }
        guard !navigation.isFollowingTrip else {
            autoZoom = .done
            return
        }

        // A restored last-known fix positions the map immediately, but the
        // real fix still gets to correct it once — hence the middle stage.
        if location.isStale {
            if autoZoom == .pending {
                focusOnMe(animated: false)
                autoZoom = .usedStaleFix
            }
            return
        }

        focusOnMe(animated: autoZoom == .usedStaleFix)
        autoZoom = .done
    }

    private func centreOnFollowedVehicle() {
        guard navigation.isFollowingTrip, let vehicle = tripPath.path?.vehicle else { return }
        let coordinate = CLLocationCoordinate2D(latitude: vehicle.lat, longitude: vehicle.lon)

        guard didCenterOnFocus else {
            // No animation on the first hit: the rider asked to follow this
            // bus, so the map should already be there.
            camera.send(.jump(coordinate, zoom: 15))
            didCenterOnFocus = true
            return
        }

        // After that first snap the map only keeps chasing until the rider
        // pans or zooms. Once they have moved it themselves, dragging the view
        // back every four seconds would make the map unusable.
        guard mapFollowsVehicle else { return }
        camera.send(.fly(coordinate, zoom: 15))
    }

    /// Keeps pinned vehicles in frame — once when the pin set changes, and
    /// continuously when "follow" is on.
    private func frameWatchedVehicles() {
        let filters = navigation.filters
        let query = filters.vq.trimmingCharacters(in: .whitespaces).lowercased()
        guard !filters.watch.isEmpty || !query.isEmpty, !navigation.isFollowingTrip else { return }

        let key = filters.watch.joined(separator: ",") + "|" + query
        let points = filteredVehicles.compactMap(\.coordinate)
        guard !points.isEmpty else {
            lastWatchKey = key
            return
        }

        if filters.follow || key != lastWatchKey {
            if points.count == 1 {
                camera.send(.flyAtLeast(points[0], minZoom: 15))
            } else {
                camera.send(.fit(points, maxZoom: 16))
            }
        }
        lastWatchKey = key
    }

    // MARK: - Derived data

    private var selectedStopBinding: Binding<Stop?> {
        Binding(
            get: {
                // While following a trip the map belongs to that vehicle; the
                // stop sheet would cover it for no reason.
                navigation.isFollowingTrip ? nil : store.stop(id: navigation.selectedStopId)
            },
            set: { if $0 == nil { navigation.selectedStopId = nil } }
        )
    }

    private var filteredVehicles: [LiveVehicle] {
        VehicleFilter.apply(
            vehicles: store.liveVehicles,
            filters: navigation.filters,
            routes: store.routes,
            position: location.position
        )
    }

    private var filterSummary: String {
        let filters = navigation.filters
        if !filters.watch.isEmpty { return "\(filters.watch.joined(separator: ", ")) követése" }
        if !filters.routes.isEmpty { return "\(filters.routes.count) járat · \(filteredVehicles.count) jármű" }
        if let km = filters.nearMeKm {
            return km < 1 ? "\(Int(km * 1000)) m sugarú körben" : "\(km.formatted()) km sugarú körben"
        }
        if filters.speed == .moving { return "Csak mozgó járművek" }
        if filters.speed == .idle { return "Csak álló járművek" }
        if filters.onlyWatched { return "Csak a figyelt megállók (\(favorites.stopIds.count))" }
        return "Szűrés aktív · \(filteredVehicles.count) jármű"
    }
}

/// Route shapes, fetched once per route and kept for the session — the
/// geometry never changes within a feed version, so re-fetching on every
/// toggle would be pure waste.
@MainActor
final class RouteShapeCache: ObservableObject {
    @Published private(set) var shapes: [String: [[CLLocationCoordinate2D]]] = [:]

    func load(routeIds: [String]) async {
        let missing = routeIds.filter { shapes[$0] == nil }
        guard !missing.isEmpty else { return }

        do {
            let response = try await APIClient.shared.routeGeo(routeIds: missing)
            for route in response.routes {
                shapes[route.id] = route.polylines
            }
        } catch {
            // Without geometry the map simply shows no route line; the rest
            // of the view keeps working.
        }
    }
}
