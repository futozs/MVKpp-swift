//
//  TimetableFeeds.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// The day's trip journal — which vehicle ran each trip, when it left and
/// arrived, how late. Port of the web's `useTripJournal`.
///
/// For today the server pushes every change on `runs:<yyyyMMdd>` the moment it
/// happens (the departure time appears as the bus leaves the terminus). A past
/// day is one fetch. REST polling only runs while the WebSocket is down.
@MainActor
final class TripJournalFeed: ObservableObject {
    @Published private(set) var trips: [String: TripJournalEntry] = [:]

    private(set) var ymd: String?
    private var pollInterval: TimeInterval = 30
    private var liveDay: String?
    private var topic: AnyCancellable?
    private var connection: AnyCancellable?
    private var pollTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var graceOver = false

    private struct RunsMessage: Decodable {
        let date: String?
        let full: [String: TripJournalEntry]?
        let upd: [String: TripJournalEntry]?
    }

    init() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            self?.graceOver = true
            self?.updatePolling()
        }
        connection = RealtimeClient.shared.$connected
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.updatePolling() }
            }
    }

    /// `pollInterval` 0 turns the fallback poll off (a settled past day).
    func set(ymd: String?, pollInterval: TimeInterval) {
        guard ymd != self.ymd || pollInterval != self.pollInterval else { return }
        let dayChanged = ymd != self.ymd
        self.ymd = ymd
        self.pollInterval = pollInterval
        if dayChanged {
            trips = [:]
            liveDay = nil
            topic = nil
            retryTask?.cancel()
            if let ymd { Task { await load(ymd) } }
        }
        updatePolling()
    }

    private func load(_ asked: String) async {
        do {
            let response = try await APIClient.shared.tripJournal(date: asked, modes: TransitMode.param())
            guard ymd == asked, response.date.replacingOccurrences(of: "-", with: "") == asked else { return }
            trips = response.trips
            if response.source == "live", liveDay != asked {
                liveDay = asked
                subscribe(asked)
                updatePolling()
            }
        } catch {
            guard ymd == asked else { return }
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.ymd == asked else { return }
                await self.load(asked)
            }
        }
    }

    private func subscribe(_ day: String) {
        topic = RealtimeClient.shared.subscribe("runs:\(day)") { [weak self] message in
            guard let self, let payload = try? message.decode(RunsMessage.self), payload.date == self.ymd else { return }
            if let full = payload.full {
                self.trips = full
            } else if let upd = payload.upd {
                self.trips.merge(upd) { _, new in new }
            }
        }
    }

    private func updatePolling() {
        let wanted = graceOver && liveDay != nil && pollInterval > 0 && !RealtimeClient.shared.connected
        guard wanted != (pollTask != nil) else { return }
        pollTask?.cancel()
        pollTask = nil
        guard wanted, let day = liveDay else { return }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load(day)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    deinit {
        pollTask?.cancel()
        retryTask?.cancel()
    }
}

/// Runs the operator pulled for a day. Port of `useCancelledTrips`: today
/// asks for the live list and refreshes every 30 s, other days fetch once.
@MainActor
final class CancelledTripsFeed: ObservableObject {
    @Published private(set) var ids: Set<String> = []
    @Published private(set) var trips: [CancelledTrip] = []

    private var key: String?
    private var task: Task<Void, Never>?
    private let pollInterval: TimeInterval = 30

    func set(ymd: String?, isToday: Bool) {
        let key = ymd.map { "\($0)|\(isToday)" }
        guard key != self.key else { return }
        self.key = key
        task?.cancel()
        ids = []
        trips = []
        guard let ymd else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load(ymd: ymd, isToday: isToday)
                guard isToday else { return }
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 30))
            }
        }
    }

    private func load(ymd: String, isToday: Bool) async {
        guard let response = try? await APIClient.shared.cancelledTrips(date: isToday ? nil : ymd, modes: TransitMode.param()),
              response.date.replacingOccurrences(of: "-", with: "") == ymd,
              key?.hasPrefix(ymd) == true
        else { return }
        ids = Set(response.tripIds)
        trips = response.trips
    }

    deinit { task?.cancel() }
}

/// A run's measured stop events — when the bus really got to each stop.
/// Port of `useTripActuals`.
struct TripStopActual: Hashable {
    let arr: Double
    let dep: Double?
    let delay: Int
    let estimated: Bool
}

@MainActor
final class TripActualsLoader: ObservableObject {
    @Published private(set) var byStop: [String: TripStopActual] = [:]
    private var key: String?

    func load(dateYmd: String, tripId: String) async {
        let key = "\(dateYmd)|\(tripId)"
        if key != self.key { byStop = [:] }
        self.key = key
        guard let response = try? await APIClient.shared.tripActuals(dateYmd: dateYmd, tripId: tripId),
              self.key == key
        else { return }
        var map: [String: TripStopActual] = [:]
        for event in response.events ?? [] where map[event.stop_id] == nil {
            map[event.stop_id] = TripStopActual(arr: event.arr, dep: event.dep, delay: event.delay_s, estimated: event.src == 3)
        }
        byStop = map
    }
}
