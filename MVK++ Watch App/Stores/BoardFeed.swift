//
//  BoardFeed.swift
//  MVK++ Watch App
//

import Combine
import Foundation
import WidgetKit

/// Live departures for a set of stops, the web `StopCard` way: the server
/// pushes each board on `stop:<id>@<board key>` as soon as it changes, and
/// the REST endpoint is polled only while the socket is down.
///
/// watchOS keeps raw sockets for audio apps on real hardware, so on a wrist
/// the polling path is the normal one; the simulator gets the pushes.
@MainActor
final class BoardFeed: ObservableObject {
    @Published private(set) var results: [String: StopArrivalsResponse] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var updatedAt: Date?

    private let limit: Int
    private let pollInterval: Duration
    private var stopIds: [String] = []
    private var boardKey = ""
    private var subscriptions: [String: AnyCancellable] = [:]
    private var pollTask: Task<Void, Never>?
    private var reloadsWidgets: Bool

    private struct Push: Decodable {
        let data: StopArrivalsResponse?
    }

    init(limit: Int = 3, pollInterval: Duration = .seconds(8), reloadsWidgets: Bool = false) {
        self.limit = limit
        self.pollInterval = pollInterval
        self.reloadsWidgets = reloadsWidgets
    }

    func track(_ stopIds: [String], boardKey: String) {
        guard stopIds != self.stopIds || boardKey != self.boardKey || pollTask == nil else { return }
        let keyChanged = boardKey != self.boardKey
        self.stopIds = stopIds
        self.boardKey = boardKey
        if keyChanged { subscriptions.removeAll() }

        let wanted = Set(stopIds)
        for id in subscriptions.keys where !wanted.contains(id) { subscriptions[id] = nil }
        results = results.filter { wanted.contains($0.key) }
        for id in stopIds where subscriptions[id] == nil {
            subscriptions[id] = RealtimeClient.shared.subscribe("stop:\(id)@\(boardKey)") { [weak self] message in
                guard let board = try? message.decode(Push.self).data else { return }
                self?.results[id] = board
                self?.updatedAt = Date()
                self?.errorMessage = nil
            }
        }

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(8))
                guard let self, !Task.isCancelled else { return }
                if !RealtimeClient.shared.connected { await self.load() }
            }
        }
    }

    func stop() {
        subscriptions.removeAll()
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        RealtimeClient.shared.wake()
        await load()
    }

    private func load() async {
        guard !stopIds.isEmpty else {
            results = [:]
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            if stopIds.count == 1, let id = stopIds.first {
                results[id] = try await APIClient.shared.arrivals(stopId: id, limit: limit, boardKey: boardKey)
            } else {
                let response = try await APIClient.shared.multiArrivals(stopIds: stopIds, limit: limit, boardKey: boardKey)
                for result in response.results { results[result.stop.id] = result }
            }
            updatedAt = Date()
            errorMessage = nil
            if reloadsWidgets {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.nextDeparture)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.watchedStops)
            }
        } catch {
            errorMessage = "Nem sikerült frissíteni"
        }
    }
}

/// Every vehicle on the road for the rider's modes (`vehicles@<modes>`), for
/// the map. Deltas over the socket, a REST snapshot while it is down.
@MainActor
final class VehicleFeed: ObservableObject {
    @Published private(set) var vehicles: [LiveVehicle] = []

    private var map: [String: LiveVehicle] = [:]
    private var subscription: AnyCancellable?
    private var pollTask: Task<Void, Never>?
    private var modes = ""

    private struct Delta: Decodable {
        let full: [Lenient<LiveVehicle>]?
        let upd: [Lenient<LiveVehicle>]?
        let del: [String]?
    }

    func start(modes: String) {
        guard modes != self.modes || subscription == nil else { return }
        self.modes = modes
        subscription = RealtimeClient.shared.subscribe("vehicles@\(modes)") { [weak self] message in
            guard let self, let delta = try? message.decode(Delta.self) else { return }
            if let full = delta.full {
                self.map = Dictionary(Array(lenient: full).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            } else {
                for vehicle in Array(lenient: delta.upd ?? []) { self.map[vehicle.id] = vehicle }
                for id in delta.del ?? [] { self.map[id] = nil }
            }
            self.publish()
        }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                if !RealtimeClient.shared.connected { await self.load() }
            }
        }
    }

    func stop() {
        subscription = nil
        pollTask?.cancel()
        pollTask = nil
    }

    private func load() async {
        guard let response = try? await APIClient.shared.livePositions(modes: modes) else { return }
        map = Dictionary(response.vehicles.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        publish()
    }

    private func publish() {
        vehicles = map.values.filter { $0.lat != nil && $0.lon != nil }
    }
}
