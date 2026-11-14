//
//  MapScreen.swift
//  MVK++ Phone App
//

import CoreLocation
import Combine
import SwiftUI

/// The live network map (`TransitMap.tsx` with the parts of `App.tsx` that
/// sit on it: the ride layer and the followed vehicle's dock). Every control
/// floating over the map is Liquid Glass, one per corner as on the web:
/// filter top left, base map / layers and 3D top right, search bottom left,
/// timeline and location bottom right.
struct MapScreen: View {

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var favorites: FavoritesStore

    @ObservedObject private var rides = RideStore.shared

    @StateObject private var camera = MapCameraController()
    @StateObject private var tripPath = TripPathModel()
    @StateObject private var shapes = RouteShapeCache()
    @StateObject private var traffic = MapTrafficModel()

    @AppStorage("mvk_map_3d") private var map3dFlag = "0"

    @State private var isFilterOpen = false
    @State private var isLayersOpen = false
    @State private var isSearchOpen = false
    @State private var historyOn = false
    @State private var popupVehicleId: String?
    @State private var popupTraffic: MapTrafficSegment?
    @State private var popupHistoryId: String?
    @State private var geoAsked = false
    @State private var coverTop: CGFloat = .infinity
    @State private var autoZoom: AutoZoomStage = .pending
    @State private var lastWatchKey = ""

    private enum AutoZoomStage { case pending, usedStaleFix, done }

    private let nearStopKm = 0.4
    private let closeZoom: Double = 17
    private let meZoom: Double = 16

    private var is3D: Bool { map3dFlag == "1" }

    var body: some View {
        GeometryReader { proxy in
            let bottom = proxy.frame(in: .global).maxY
            let cover = coverTop.isFinite ? max(0, bottom - coverTop) : 0
            ZStack {
                map(cover: cover)
                controls(cover: cover)
                popups(cover: cover)
                RideLayer(
                    vehicles: store.liveVehicles,
                    followingTripId: navigation.focusTripId,
                    onFollow: { tripId, vehicleId in navigation.focusTrip(tripId, vehicleId: vehicleId) },
                    onStopFollow: { navigation.exitFocus() }
                )
                dock
                if historyOn { timeline }
                if isFilterOpen { filterDrawer }
                if isSearchOpen { searchSheet }
            }
            .onPreferenceChange(MapCoverKey.self) { coverTop = $0 }
        }
        .toolbar(navigation.isFollowingTrip || historyOn ? .hidden : .visible, for: .tabBar)
        .animation(Theme.Motion.normalAnimation, value: navigation.isFollowingTrip)
        .animation(Theme.Motion.normalAnimation, value: isFilterOpen)
        .animation(Theme.Motion.normalAnimation, value: isSearchOpen)
        .animation(Theme.Motion.normalAnimation, value: historyOn)
        .sheet(item: selectedStopBinding) { stop in
            StopDetailSheet(
                stop: stop,
                isMonitored: favorites.contains(stop.id),
                onToggleMonitor: favorites.toggle,
                onFocusTrip: { tripId, vehicleId in navigation.focusTrip(tripId, vehicleId: vehicleId) }
            )
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .task(id: navigation.filters.shape ? navigation.filters.routes : []) {
            await shapes.load(routeIds: navigation.filters.shape ? navigation.filters.routes : [])
        }
        .onChange(of: navigation.focusTripId) { _, tripId in
            popupVehicleId = nil
            if tripId != nil { historyOn = false }
            tripPath.follow(tripId: tripId, vehicleId: navigation.focusVehicleId)
        }
        .onChange(of: navigation.focusVehicleId) { _, vehicleId in
            tripPath.follow(tripId: navigation.focusTripId, vehicleId: vehicleId)
        }
        .onChange(of: navigation.selectedStopId) { _, stopId in
            guard let stop = store.stop(id: stopId) else { return }
            camera.send(.flyAtLeast(CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon), minZoom: closeZoom))
        }
        .onChange(of: location.position) { _, _ in runAutoZoom() }
        .onChange(of: store.stops.count) { _, _ in runAutoZoom() }
        .onChange(of: store.liveVehicles) { _, _ in frameWatchedVehicles() }
        .onChange(of: navigation.filters) { _, _ in frameWatchedVehicles() }
        .onChange(of: navigation.filters.traffic) { _, on in traffic.setEnabled(on && !historyOn) }
        .onChange(of: historyOn) { _, on in
            traffic.setEnabled(navigation.filters.traffic && !on)
            popupVehicleId = nil
            popupHistoryId = nil
        }
        .onAppear {
            tripPath.follow(tripId: navigation.focusTripId, vehicleId: navigation.focusVehicleId)
            traffic.setEnabled(navigation.filters.traffic && !historyOn)
            store.startPolling()
            runAutoZoom()
        }
    }

    // MARK: - Map

    private func map(cover: CGFloat) -> some View {
        TransitMapRepresentable(
            stops: store.stops,
            routes: store.routes,
            vehicles: store.liveVehicles,
            visibleVehicles: filteredVehicles,
            filters: navigation.filters,
            tileLayer: navigation.tileLayer,
            selectedStopId: navigation.selectedStopId,
            monitoredStopIds: favorites.stopIds,
            focusTripId: navigation.focusTripId,
            focusVehicleId: navigation.focusVehicleId,
            focusPath: tripPath.path,
            routeShapes: shapes.shapes,
            traffic: traffic.segments,
            userPosition: location.position,
            ridePosition: location.isActive && !location.isStale ? location.position : nil,
            riddenVehicleId: rides.active?.vehicleId,
            is3D: is3D,
            historyOn: historyOn,
            coverBottom: cover,
            camera: camera,
            onSelectStop: { navigation.selectedStopId = $0 },
            onSelectVehicle: { id in
                popupTraffic = nil
                popupVehicleId = id
            },
            onSelectHistoryVehicle: { popupHistoryId = $0 },
            onSelectTraffic: { segment in
                popupVehicleId = nil
                popupTraffic = segment
            },
            onTapMap: {
                popupVehicleId = nil
                popupTraffic = nil
                popupHistoryId = nil
            }
        )
        .ignoresSafeArea()
    }

    // MARK: - Corners

    private func controls(cover: CGFloat) -> some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    topLeft
                    Spacer(minLength: 8)
                    topRight
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 8) {
                    if !historyOn { bottomLeft }
                    Spacer(minLength: 8)
                    bottomRight
                }
                .padding(.bottom, bottomInset(cover: cover))
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func bottomInset(cover: CGFloat) -> CGFloat {
        if historyOn { return 150 }
        return cover > 0 ? max(0, cover - 20) : 0
    }

    @ViewBuilder
    private var topLeft: some View {
        if let _ = navigation.focusTripId {
            HStack(spacing: 8) {
                MapControlButton(systemImage: "arrow.left", label: "Követés vége", showLabel: true, active: true) {
                    navigation.exitFocus()
                }
                if camera.followPaused {
                    MapControlButton(systemImage: "scope", label: "Busz középre", showLabel: true) {
                        camera.resumeFollow()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(Theme.Motion.fastAnimation, value: camera.followPaused)
        } else {
            let active = navigation.filters.activeCount
            HStack(spacing: 8) {
                MapControlButton(systemImage: "slider.horizontal.3", label: "Szűrés", showLabel: true, active: active > 0, badge: active > 0 ? active : nil) {
                    isFilterOpen = true
                }
                if active > 0 {
                    HStack(spacing: 4) {
                        Button {
                            isFilterOpen = true
                        } label: {
                            Text(MapFilterSummary.text(navigation.filters, routes: store.routes, visible: filteredVehicles.count))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                        Button {
                            navigation.clearFilters()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.mutedForeground)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Szűrők törlése")
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .frame(height: 44)
                    .glassEffect(.regular.tint(Theme.primary.opacity(0.12)), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.primary.opacity(0.4)))
                }
            }
        }
    }

    private var topRight: some View {
        VStack(alignment: .trailing, spacing: 8) {
            MapControlButton(systemImage: "square.3.layers.3d", label: "Térkép", active: isLayersOpen) {
                isLayersOpen.toggle()
            }
            .popover(isPresented: $isLayersOpen, arrowEdge: .top) {
                MapLayersMenu(tileLayerId: $navigation.tileLayerId, filters: $navigation.filters, watchedStops: favorites.stopIds.count)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Theme.card.opacity(0.95))
            }
            MapControlButton(systemImage: "cube", label: "3D", showLabel: true, active: is3D) {
                if !is3D, historyOn { historyOn = false }
                map3dFlag = is3D ? "0" : "1"
            }
            .accessibilityHint(is3D ? "Vissza a 2D térképre" : "3D város: épületek, domborzat, követés a busz mögül")
        }
    }

    private var bottomLeft: some View {
        MapControlButton(systemImage: "magnifyingglass", label: "Keresés", active: isSearchOpen) {
            isSearchOpen = true
        }
    }

    private var bottomRight: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let message = location.errorMessage, geoAsked || location.status != .denied {
                MapNotice(text: message)
            }
            if !historyOn, navigation.focusTripId == nil {
                MapControlButton(systemImage: "clock.arrow.circlepath", label: "Idővonal") {
                    openHistory()
                }
                .accessibilityHint("Visszanézhető, merre jártak a járművek")
            }
            MapControlButton(
                systemImage: "location.fill",
                label: location.position == nil ? "Helymeghatározás bekapcsolása" : "Ugrás a helyzetemre",
                active: location.isActive,
                busy: location.status == .requesting,
                action: handleLocate
            )
            .disabled(location.status == .requesting)
        }
    }

    // MARK: - Panels

    @ViewBuilder
    private var dock: some View {
        if let tripId = navigation.focusTripId, rides.active == nil, !historyOn {
            VStack {
                Spacer(minLength: 0)
                FocusDock(
                    tripId: tripId,
                    vehicleId: navigation.focusVehicleId,
                    stops: store.stops,
                    routes: store.routes,
                    model: tripPath,
                    followPaused: camera.followPaused,
                    onClose: { navigation.exitFocus() }
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func popups(cover: CGFloat) -> some View {
        VStack {
            Spacer(minLength: 0)
            Group {
                if let id = popupVehicleId, let vehicle = store.liveVehicles.first(where: { $0.id == id }) {
                    MapVehiclePopup(
                        vehicle: vehicle,
                        actions: rides.active == nil,
                        onFollow: {
                            popupVehicleId = nil
                            navigation.focusTrip(vehicle.tripId, vehicleId: vehicle.id)
                        },
                        onBoard: {
                            popupVehicleId = nil
                            RideBoarding.board(vehicle: vehicle, detected: .manual)
                        },
                        onClose: { popupVehicleId = nil }
                    )
                } else if let segment = popupTraffic {
                    MapTrafficPopup(segment: segment) { popupTraffic = nil }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 72 + cover)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(Theme.Motion.normalAnimation, value: popupVehicleId)
        .animation(Theme.Motion.normalAnimation, value: popupTraffic?.id)
    }

    private var timeline: some View {
        VStack {
            Spacer(minLength: 0)
            MapTimelineBar(
                routes: store.routes,
                filters: navigation.filters,
                camera: camera,
                selectedHistoryId: $popupHistoryId,
                onExit: { historyOn = false }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var filterDrawer: some View {
        ZStack(alignment: .leading) {
            Theme.background.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { isFilterOpen = false }
                .accessibilityLabel("Szűrés bezárása")
                .transition(.opacity)
            GeometryReader { proxy in
                MapFilterPanel(
                    filters: $navigation.filters,
                    routes: store.routes,
                    vehicles: store.liveVehicles,
                    visibleVehicles: filteredVehicles,
                    hasPosition: location.position != nil,
                    onClear: { navigation.clearFilters() },
                    onClose: { isFilterOpen = false },
                    onStartGeo: { location.start() },
                    onPickVehicle: { v in
                        flyToVehicle(v)
                        isFilterOpen = false
                    }
                )
                .frame(width: min(360, proxy.size.width * 0.88))
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
                .mvkShadow(Theme.Shadow.xl)
            }
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
        .zIndex(10)
    }

    private var searchSheet: some View {
        ZStack(alignment: .bottom) {
            Theme.background.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { isSearchOpen = false }
                .accessibilityLabel("Keresés bezárása")
                .transition(.opacity)
            MapSearchPanel(
                stops: store.stops,
                vehicles: store.liveVehicles,
                position: location.position,
                monitoredStopIds: favorites.stopIds,
                watched: navigation.filters.watch,
                onToggleMonitorStop: favorites.toggle,
                onPickStop: pickStop,
                onPickPlace: { camera.send(.fly($0, zoom: 16)) },
                onPickVehicle: flyToVehicle,
                onToggleWatch: { id in
                    var f = navigation.filters
                    if f.watch.contains(id) {
                        f.watch.removeAll { $0 == id }
                    } else if f.watch.count < FilterState.maxWatched {
                        f.watch.append(id)
                    }
                    navigation.filters = f
                },
                onClose: { isSearchOpen = false }
            )
            .frame(maxHeight: UIScreen.main.bounds.height * 0.72)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.xl, topTrailingRadius: Theme.Radius.xl, style: .continuous))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.xl, topTrailingRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border))
            .mvkShadow(Theme.Shadow.xl)
            .transition(.move(edge: .bottom))
        }
        .zIndex(10)
    }

    // MARK: - Actions

    private func openHistory() {
        if navigation.focusTripId != nil { navigation.exitFocus() }
        isFilterOpen = false
        if is3D { map3dFlag = "0" }
        historyOn = true
    }

    private func pickStop(_ stop: Stop) {
        camera.send(.flyAtLeast(CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon), minZoom: closeZoom))
        navigation.selectedStopId = stop.id
    }

    /// Volán / train: following (their signal lags, and the follow estimates
    /// and centres them); otherwise fly to the vehicle.
    private func flyToVehicle(_ v: LiveVehicle) {
        if TransitIds.isRegional(v.id), !v.tripId.isEmpty {
            navigation.focusTrip(v.tripId, vehicleId: v.id)
            return
        }
        if let coordinate = v.coordinate { camera.send(.fly(coordinate, zoom: 16)) }
    }

    private func handleLocate() {
        geoAsked = true
        guard location.position != nil else {
            location.start()
            return
        }
        focusOnMe(animated: true)
    }

    /// The rider together with the nearest stop when one is within walking distance.
    private func focusOnMe(animated: Bool) {
        guard let position = location.position else { return }
        let me = position.coordinate
        if let hit = Geo.nearest(store.stops, lat: position.lat, lon: position.lon), hit.km <= nearStopKm {
            camera.send(.fit([me, CLLocationCoordinate2D(latitude: hit.item.lat, longitude: hit.item.lon)], maxZoom: closeZoom))
            return
        }
        camera.send(animated ? .fly(me, zoom: meZoom) : .jump(me, zoom: meZoom))
    }

    private func runAutoZoom() {
        guard autoZoom != .done, location.position != nil, !store.stops.isEmpty else { return }
        guard navigation.focusTripId == nil else {
            autoZoom = .done
            return
        }
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

    /// Searched / pinned plates: the map jumps to them — not while following.
    private func frameWatchedVehicles() {
        let filters = navigation.filters
        let query = filters.vq.trimmingCharacters(in: .whitespaces).lowercased()
        guard !historyOn, navigation.focusTripId == nil, !filters.watch.isEmpty || !query.isEmpty else { return }
        let key = filters.watch.joined(separator: ",") + "|" + query
        let points = filteredVehicles.compactMap(\.coordinate)
        if !points.isEmpty, filters.follow || key != lastWatchKey {
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
            get: { navigation.focusTripId != nil ? nil : store.stop(id: navigation.selectedStopId) },
            set: { if $0 == nil { navigation.selectedStopId = nil } }
        )
    }

    private var filteredVehicles: [LiveVehicle] {
        VehicleFilter.sorted(
            VehicleFilter.apply(vehicles: store.liveVehicles, filters: navigation.filters, routes: store.routes, position: location.position),
            by: navigation.filters.sort
        )
    }
}

/// Route shapes, fetched once per route and kept for the session.
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
            // Without geometry the map simply shows no route line.
        }
    }
}
