//
//  StopArrivalsModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

extension APIClient {
    /// A stop's board in the enabled modes, with shared stops merged as set
    /// (`board` is the `LocalStore.boardKey`).
    func boardArrivals(stopId: String, limit: Int, board: String) async throws -> StopArrivalsResponse {
        try await request(
            path: "/live/arrivals",
            queryItems: [
                URLQueryItem(name: "stop", value: stopId),
                URLQueryItem(name: "limit", value: String(limit)),
            ] + TransitModes.boardQueryItems(board)
        )
    }
}

/// One stop's departures. The server pushes the board over the WebSocket
/// (`stop:<id>@<board>`) as soon as it changes; REST polling only runs while
/// there is no live connection. A failed load retries on its own, backing off
/// from 3 s to 30 s. With no gateway at all the downloaded timetable answers.
@MainActor
final class StopArrivalsModel: ObservableObject {
    @Published private(set) var response: StopArrivalsResponse?
    @Published private(set) var arrivals: [ArrivalItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: FriendlyError?
    @Published private(set) var hasLiveData = false
    /// The list came out of the downloaded timetable because the gateway
    /// could not be reached.
    @Published private(set) var isOffline = false

    var errorMessage: String? { error?.reason }

    private static let pollInterval: Duration = .seconds(4)
    /// Wait this long for the socket before falling back to polling.
    private static let connectGrace: Duration = .milliseconds(2500)
    private static let retryBase: Double = 3
    private static let retryMax: Double = 30
    /// A single dropped load on a moving phone is normal; past this the
    /// connection is genuinely gone and the timetable takes over.
    private static let staleAfter: TimeInterval = 45

    private var stopId = ""
    private var stopName = ""
    private var limit = 8
    private var board = ""
    private var subscription: AnyCancellable?
    private var pollTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryDelay = retryBase
    private var lastSuccessAt: Date?
    private var observers: Set<AnyCancellable> = []

    func start(stopId: String, stopName: String = "", limit: Int = 16) async {
        let board = LocalStore.shared.boardKey
        if self.stopId == stopId, self.board == board, self.limit == limit, subscription != nil { return }
        stop()
        if self.stopId != stopId {
            response = nil
            arrivals = []
            error = nil
            isOffline = false
            lastSuccessAt = nil
        }
        self.stopId = stopId
        self.stopName = stopName
        self.limit = limit
        self.board = board
        retryDelay = Self.retryBase
        isLoading = response == nil

        subscription = RealtimeClient.shared.subscribe("stop:\(stopId)@\(board)") { [weak self] message in
            guard let push = try? message.decode(StopPush.self), let data = push.data else { return }
            self?.apply(data)
        }

        RealtimeClient.shared.$connected
            .removeDuplicates()
            .sink { [weak self] connected in self?.connectionChanged(connected) }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.boardMaybeChanged() }
            .store(in: &observers)

        await load()
    }

    func stop() {
        subscription = nil
        pollTask?.cancel()
        pollTask = nil
        retryTask?.cancel()
        retryTask = nil
        observers.removeAll()
    }

    private func boardMaybeChanged() {
        guard !stopId.isEmpty, LocalStore.shared.boardKey != board else { return }
        let id = stopId, name = stopName, limit = limit
        Task { await start(stopId: id, stopName: name, limit: limit) }
    }

    private func connectionChanged(_ connected: Bool) {
        pollTask?.cancel()
        pollTask = nil
        guard !connected else { return }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: Self.connectGrace)
            while !Task.isCancelled {
                guard let self else { return }
                if !RealtimeClient.shared.connected { await self.load() }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func load() async {
        let id = stopId
        do {
            let result = try await APIClient.shared.boardArrivals(stopId: id, limit: limit, board: board)
            guard id == stopId else { return }
            apply(result)
        } catch {
            guard id == stopId, !(error is CancellationError) else { return }
            failed(error)
        }
    }

    private func apply(_ result: StopArrivalsResponse) {
        response = result
        arrivals = result.arrivals
        hasLiveData = result.rtError == nil
        isOffline = false
        error = nil
        isLoading = false
        lastSuccessAt = Date()
        retryDelay = Self.retryBase
        retryTask?.cancel()
        retryTask = nil

        NotificationCenterStore.shared.scheduleAlarm(
            stopId: stopId,
            stopName: stopName.isEmpty ? (result.stop.name ?? stopId) : stopName,
            arrivals: result.arrivals
        )
        AlertsStore.shared.boardUpdated(stopId: stopId, arrivals: result.arrivals)
    }

    private func failed(_ failure: Error) {
        error = FriendlyError(failure)
        isLoading = false
        fallBackToSchedule()

        retryTask?.cancel()
        let delay = retryDelay
        retryDelay = min(Self.retryMax, retryDelay * 2)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            await self.load()
        }
    }

    /// No gateway: the downloaded timetable knows when the bus is *supposed*
    /// to come. Every row is schedule-only, so nobody reads a prediction into it.
    private func fallBackToSchedule() {
        let isStale = lastSuccessAt.map { Date().timeIntervalSince($0) > Self.staleAfter } ?? true
        guard isStale || arrivals.isEmpty else { return }

        let scheduled = OfflineDepartures.arrivals(stopId: stopId, limit: limit)
        guard !scheduled.isEmpty else {
            if isOffline { arrivals = [] }
            return
        }
        arrivals = scheduled
        hasLiveData = false
        isOffline = true
        NotificationCenterStore.shared.scheduleAlarm(
            stopId: stopId,
            stopName: stopName.isEmpty ? stopId : stopName,
            arrivals: scheduled
        )
    }

    private struct StopPush: Decodable {
        let data: StopArrivalsResponse?
    }
}
