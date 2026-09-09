//
//  TransitStore.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// The network's shared state: the static GTFS catalog, loaded once, and the
/// live vehicle feed, refreshed on a timer. Every tab reads from here rather
/// than fetching its own copy of the stop list.
@MainActor
final class TransitStore: ObservableObject {

    @Published private(set) var stops: [Stop] = []
    @Published private(set) var routes: [String: Route] = [:]
    @Published private(set) var gtfsMeta: GtfsMeta?
    @Published private(set) var liveVehicles: [LiveVehicle] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var staticError: String?
    /// The catalog on screen came from the device, not the gateway. Screens
    /// read this to say so instead of quietly showing yesterday as today.
    @Published private(set) var isUsingOfflineCatalog = false

    /// The upstream feed publishes roughly every three seconds; polling
    /// slightly faster than that keeps the map from visibly stepping.
    private let pollInterval: TimeInterval = 3.5

    private var hasLoadedStatic = false
    private var pollTask: Task<Void, Never>?

    private lazy var stopIndex: [String: Stop] = [:]

    func stop(id: String?) -> Stop? {
        guard let id else { return nil }
        return stopIndex[id]
    }

    func route(id: String) -> Route? { routes[id] }

    // MARK: - Static catalog

    func loadStaticIfNeeded() async {
        guard !hasLoadedStatic else { return }
        await loadStatic()
    }

    func loadStatic() async {
        do {
            let catalog = try await APIClient.shared.staticCatalog()

            apply(stops: catalog.stops, routes: catalog.routes, meta: catalog.meta, offline: false)
            hasLoadedStatic = true
            staticError = nil

            // The widget's stop picker and its "which stop is this" lookup
            // both read this copy; a widget extension has no time for a cold
            // network call and no business making one. The offline catalog on
            // the next launch without signal is the same mirror.
            SharedStopCache.save(catalog.stops)
            SharedCatalogCache.saveRoutes(catalog.routesData)
            SharedCatalogCache.saveMeta(catalog.metaData)
        } catch {
            // No signal is the normal case this app has to survive, not an
            // error state. If the catalog was ever downloaded it is still on
            // the device, and every screen that only needs stop names, route
            // colours and the timetable keeps working from it.
            if loadOfflineCatalog() {
                staticError = nil
            } else {
                staticError = error.localizedDescription
            }
        }
    }

    /// Rehydrates from the App Group mirror. Returns false when there is
    /// nothing stored — a first launch that never reached the network.
    @discardableResult
    private func loadOfflineCatalog() -> Bool {
        let cachedStops = SharedStopCache.loadStops()
        guard !cachedStops.isEmpty else { return false }

        apply(
            stops: cachedStops,
            routes: SharedCatalogCache.routes(),
            meta: SharedCatalogCache.meta(),
            offline: true
        )
        // Deliberately not `hasLoadedStatic`: the next chance at the network
        // should still be taken.
        return true
    }

    private func apply(stops loadedStops: [Stop], routes loadedRoutes: [Route], meta: GtfsMeta?, offline: Bool) {
        stops = loadedStops
        stopIndex = Dictionary(loadedStops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if !loadedRoutes.isEmpty {
            routes = Dictionary(loadedRoutes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        if let meta { gtfsMeta = meta }
        isUsingOfflineCatalog = offline
    }

    // MARK: - Live positions

    /// Polling pauses while a single trip is being followed: that screen reads
    /// `/live/trip-path` instead, and the full fleet would be wasted traffic.
    func startPolling(paused: Bool = false) {
        stopPolling()
        guard !paused else { return }

        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshLive()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshLive() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let response = try await APIClient.shared.livePositions()
            // Vehicles without a fix cannot be drawn and must not be counted.
            liveVehicles = response.vehicles.filter { $0.lat != nil && $0.lon != nil }
            lastUpdated = Date()
        } catch {
            // A dropped poll is normal on a moving phone; the next tick
            // recovers, and blanking the map would be worse than stale dots.
        }
    }

    deinit { pollTask?.cancel() }
}
