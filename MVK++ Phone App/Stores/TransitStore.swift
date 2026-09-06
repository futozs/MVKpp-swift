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
            async let stopsTask = APIClient.shared.stops()
            async let routesTask = APIClient.shared.routes()
            async let metaTask = APIClient.shared.gtfsMeta()

            let (loadedStops, loadedRoutes, meta) = try await (stopsTask, routesTask, metaTask)

            stops = loadedStops
            stopIndex = Dictionary(loadedStops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            routes = Dictionary(loadedRoutes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            gtfsMeta = meta
            hasLoadedStatic = true
            staticError = nil
        } catch {
            staticError = error.localizedDescription
        }
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
