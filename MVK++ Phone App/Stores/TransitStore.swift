//
//  TransitStore.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// The network's shared state: the static GTFS catalog of the enabled modes
/// and the live vehicle feed. Every tab reads from here rather than fetching
/// its own copy of the stop list (web `App.tsx`).
///
/// Live vehicles arrive over the shared WebSocket on `vehicles@<modes>`:
/// the full list on subscribe, then only the vehicles that changed. REST
/// polling runs only while that channel is down.
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
    /// The `?modes=` value the catalog and the live feed were loaded for.
    @Published private(set) var modesKey: String

    /// The upstream feed publishes roughly every three seconds; the fallback
    /// poll runs slightly faster so the map does not visibly step.
    private let pollInterval: Duration = .milliseconds(3500)
    /// Wait this long for the socket before starting to poll.
    private let connectGrace: Duration = .milliseconds(2500)
    /// While the worker builds the Volán and rail timetables, the catalog is
    /// asked for again this often.
    private let regionalRetry: Duration = .seconds(45)

    private var hasLoadedStatic = false
    private var staticTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var vehicleSubscription: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []
    private var vehicleMap: [String: LiveVehicle] = [:]
    private var stopIndex: [String: Stop] = [:]

    init() {
        modesKey = LocalStore.shared.modesParam
        LocalStore.shared.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.modesMayHaveChanged() }
            .store(in: &cancellables)
    }

    func stop(id: String?) -> Stop? {
        guard let id else { return nil }
        return stopIndex[id]
    }

    func route(id: String) -> Route? { routes[id] }

    func vehicle(id: String) -> LiveVehicle? { vehicleMap[id] }

    /// Stops for the map and the stop search: a Volán twin of an MVK pole is
    /// not a separate dot in the merged view (`useStopMerge`).
    var mapStops: [Stop] {
        let merge = LocalStore.shared.stopMerge
        guard merge != .off else { return stops }
        return stops.filter { !TransitModes.isMergedTwin($0, merge: merge) }
    }

    // MARK: - Modes

    private func modesMayHaveChanged() {
        let next = LocalStore.shared.modesParam
        guard next != modesKey else { return }
        modesKey = next
        hasLoadedStatic = false
        staticTask?.cancel()
        staticTask = Task { await self.loadStatic() }
        if vehicleSubscription != nil { subscribeVehicles() }
    }

    // MARK: - Static catalog

    func loadStaticIfNeeded() async {
        guard !hasLoadedStatic else { return }
        if staticTask == nil { staticTask = Task { await self.loadStatic() } }
        await staticTask?.value
    }

    /// Weak signal or a restarting worker can fail the first request, so it is
    /// retried with growing backoff; an empty map would be worse.
    func loadStatic() async {
        var attempt = 0
        while !Task.isCancelled {
            let modes = modesKey
            do {
                let catalog = try await APIClient.shared.staticCatalog(modes: modes)
                guard modes == modesKey else { return }
                apply(stops: catalog.stops, routes: catalog.routes, meta: catalog.meta, offline: false)
                hasLoadedStatic = true
                staticError = nil

                // The widget's stop picker and the next launch without signal
                // both read this mirror.
                SharedStopCache.save(catalog.stops)
                SharedCatalogCache.saveRoutes(catalog.routesData)
                SharedCatalogCache.saveMeta(catalog.metaData)

                // For minutes after a start the worker serves MVK only; the
                // stations (Tiszai, Gömöri) would be missing until a reload.
                if catalog.meta.regional == "pending", modes.contains("coach") || modes.contains("rail") {
                    hasLoadedStatic = false
                    try? await Task.sleep(for: regionalRetry)
                    continue
                }
                return
            } catch {
                if Task.isCancelled { return }
                if stops.isEmpty {
                    if loadOfflineCatalog() {
                        staticError = nil
                    } else {
                        staticError = error.localizedDescription
                    }
                }
                attempt += 1
                let delay = min(30.0, 1.5 * pow(2, Double(min(attempt, 5))))
                try? await Task.sleep(for: .seconds(delay))
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

    /// Starts the live feed: the WebSocket topic, plus the REST fallback that
    /// only polls while the socket is down. Following a trip keeps it running —
    /// the header count, the boarding detector and the timetable's live marks
    /// all read it.
    func startLive() {
        if vehicleSubscription == nil { subscribeVehicles() }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let grace = self?.connectGrace else { return }
            try? await Task.sleep(for: grace)
            while !Task.isCancelled {
                guard let self else { return }
                if !RealtimeClient.shared.connected { await self.refreshLive() }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func startPolling(paused: Bool = false) {
        startLive()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func subscribeVehicles() {
        // The topic carries the modes: switching them makes the server send
        // the full new list.
        vehicleSubscription = RealtimeClient.shared.subscribe("vehicles@\(modesKey)") { [weak self] message in
            self?.handleVehicles(message)
        }
    }

    private struct VehicleDelta: Decodable {
        let full: [LiveVehicle]?
        let upd: [LiveVehicle]?
        let del: [String]?
    }

    private func handleVehicles(_ message: RealtimeMessage) {
        guard let delta = try? message.decode(VehicleDelta.self) else { return }
        if let full = delta.full {
            vehicleMap = Dictionary(full.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        } else {
            for vehicle in delta.upd ?? [] { vehicleMap[vehicle.id] = vehicle }
            for id in delta.del ?? [] { vehicleMap[id] = nil }
        }
        publishVehicles()
    }

    private func publishVehicles() {
        // Vehicles without a fix cannot be drawn and must not be counted.
        liveVehicles = vehicleMap.values
            .filter { $0.lat != nil && $0.lon != nil }
            .sorted { $0.id < $1.id }
        lastUpdated = Date()
    }

    /// One REST snapshot — the fallback tick and the manual "Frissítés most".
    func refreshLive() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let response = try await APIClient.shared.livePositions(modes: modesKey)
            let valid = response.vehicles.filter { $0.lat != nil && $0.lon != nil }
            vehicleMap = Dictionary(valid.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            publishVehicles()
        } catch {
            // A dropped poll is normal on a moving phone; the next tick
            // recovers, and blanking the map would be worse than stale dots.
        }
    }

    /// Back in the foreground: reconnect at once. With a live socket the
    /// WebSocket brings fresh state; a REST snapshot (without motion
    /// estimates) would snap the buses back to their raw fix.
    func wake() {
        RealtimeClient.shared.wake()
        if !RealtimeClient.shared.connected {
            Task { await refreshLive() }
        }
        if !hasLoadedStatic, staticTask == nil {
            staticTask = Task { await self.loadStatic() }
        }
        // `staticTask` stays set once started: it retries on its own until the
        // catalog arrives.
    }

    deinit {
        pollTask?.cancel()
        staticTask?.cancel()
    }
}
