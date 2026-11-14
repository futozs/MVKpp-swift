//
//  RideFeeds.swift
//  MVK++ Phone App
//
//  The ride's live data: the trip (`useTripLive`), the bus's continuation
//  at the terminus (`useContinuation`) and congestion ahead (`useTrafficAhead`).
//

import Combine
import Foundation

/// A trip live: stops, measured events, position, delay and forecast.
struct TripLive: Equatable {
    let tripId: String
    /// The terminus is a turning loop (staying seated goes round).
    var loopEnd: Bool
    var stops: [TripStop]
    var events: [RideStopEvent]
    var run: TripRun?
    var delayS: Double?
    var forecast: [Int: ForecastStop]
    var vehicle: TripLiveVehicle?
    /// The trip's short name (rail: „5169 személyvonat”, Volán: „4001/748”).
    var tripShort: String?

    var passed: Int { run?.lastStopIdx ?? -1 }
    var times: [Int: RideStopTime] { RideLogic.stopTimes(events) }
}

/// Congested link on the rest of the trip: between stop `fromIdx` and the next.
struct TrafficAhead: Equatable {
    let fromIdx: Int
    let excessS: Double
    let level: Double
}

/// `useTripLive`: one fetch of `/engine/trip`, then the `trip:<id>` topic;
/// REST every 15 s only while the socket is down. A trip on another service
/// day has no live stream — the fetch gives its final state.
@MainActor
final class TripLiveFeed {
    private(set) var value: TripLive?
    var onChange: ((TripLive?) -> Void)?

    private let tripId: String
    private let date: String?
    private let isToday: Bool
    private var subscription: AnyCancellable?
    private var connection: AnyCancellable?
    private var pollTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var lastPassed: Int?

    private struct Push: Decodable {
        struct Payload: Decodable {
            /// A push without the key leaves the bus where it was (web
            /// `useTripLive`: `"vehicle" in m`); an explicit null clears it.
            let hasVehicle: Bool
            let vehicle: LossyVehicle?
            let run: TripRun?
            let measuredDelaySec: Double?
            let forecast: RideTripForecast?

            private enum CodingKeys: String, CodingKey {
                case vehicle, run, measuredDelaySec, forecast
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                hasVehicle = c.contains(.vehicle)
                vehicle = try c.decodeIfPresent(LossyVehicle.self, forKey: .vehicle)
                run = try c.decodeIfPresent(TripRun.self, forKey: .run)
                measuredDelaySec = try c.decodeIfPresent(Double.self, forKey: .measuredDelaySec)
                forecast = try c.decodeIfPresent(RideTripForecast.self, forKey: .forecast)
            }
        }
        let data: Payload?
    }

    private struct LossyVehicle: Decodable {
        let vehicle: TripLiveVehicle?
        init(from decoder: Decoder) throws { vehicle = try? TripLiveVehicle(from: decoder) }
    }

    init(tripId: String, date: String?) {
        self.tripId = tripId
        self.date = date
        let today = ServiceClock.at(Int(RealtimeClient.shared.serverNow)).iso
        isToday = date == nil || date == today
    }

    func start() {
        load()
        let realtime = RealtimeClient.shared
        subscription = realtime.subscribe("trip:\(tripId)") { [weak self] message in
            guard let self, self.isToday, let push = try? message.decode(Push.self), let data = push.data else { return }
            self.applyPush(data)
        }
        connection = realtime.$connected
            .removeDuplicates()
            .sink { [weak self] connected in self?.fallback(connected: connected) }
    }

    func stop() {
        subscription = nil
        connection = nil
        pollTask?.cancel()
        loadTask?.cancel()
    }

    private func fallback(connected: Bool) {
        pollTask?.cancel()
        guard !connected else { return }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            while !Task.isCancelled {
                self?.load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func load() {
        loadTask?.cancel()
        let tripId = tripId, date = date
        loadTask = Task { [weak self] in
            guard let detail = try? await APIClient.shared.rideTrip(tripId: tripId, date: date), !Task.isCancelled else { return }
            self?.applyDetail(detail)
        }
    }

    private func applyDetail(_ d: TripDetailResponse) {
        let fc = d.forecast?.stops ?? []
        let prev = value
        value = TripLive(
            tripId: tripId,
            loopEnd: d.loopEnd ?? false,
            stops: d.stops ?? [],
            events: d.events ?? [],
            run: d.run ?? prev?.run,
            delayS: d.liveDelaySec ?? d.run?.lastDelayS ?? prev?.delayS,
            forecast: fc.isEmpty ? (prev?.forecast ?? [:]) : Dictionary(fc.map { ($0.idx, $0) }, uniquingKeysWith: { a, _ in a }),
            vehicle: prev?.vehicle,
            tripShort: d.tripShort
        )
        lastPassed = value?.passed
        onChange?(value)
    }

    private func applyPush(_ m: Push.Payload) {
        guard var next = value else { return }
        let fc = m.forecast?.stops ?? []
        next.run = m.run ?? next.run
        next.delayS = m.measuredDelaySec ?? m.run?.lastDelayS ?? next.delayS
        if !fc.isEmpty { next.forecast = Dictionary(fc.map { ($0.idx, $0) }, uniquingKeysWith: { a, _ in a }) }
        if m.hasVehicle { next.vehicle = m.vehicle?.vehicle }
        value = next
        onChange?(value)
        // A new stop event (the bus left a stop): reload the measured times.
        if let passed = next.run?.lastStopIdx, passed != lastPassed {
            lastPassed = passed
            load()
        }
    }
}

/// `useContinuation`: how the bus carries on from the terminus, every 10 s.
@MainActor
final class ContinuationFeed {
    var onChange: ((Continuation?) -> Void)?
    private var task: Task<Void, Never>?

    func start(tripId: String, vehicleId: String) {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let c = try? await APIClient.shared.continuation(tripId: tripId, vehicleId: vehicleId), !Task.isCancelled {
                    self?.onChange?(c)
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// `useTrafficAhead`: the live congestion layer, every 30 s.
@MainActor
final class TrafficFeed {
    var onChange: (([LiveTrafficSegment]) -> Void)?
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let segments = try? await APIClient.shared.liveTraffic(), !Task.isCancelled {
                    self?.onChange?(segments)
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    static func ahead(_ segments: [LiveTrafficSegment], stops: [TripStop], from: Int, to: Int) -> [TrafficAhead] {
        guard !stops.isEmpty, !segments.isEmpty else { return [] }
        let byLink = Dictionary(segments.map { ("\($0.fromId)|\($0.toId)", $0) }, uniquingKeysWith: { a, _ in a })
        let lo = max(0, from)
        let hi = min(to, stops.count - 1)
        guard lo < hi else { return [] }
        return (lo..<hi).compactMap { i in
            byLink["\(stops[i].id)|\(stops[i + 1].id)"].map { TrafficAhead(fromIdx: i, excessS: $0.excessS, level: $0.level) }
        }
    }
}
