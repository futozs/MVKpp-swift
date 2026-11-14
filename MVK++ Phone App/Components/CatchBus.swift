//
//  CatchBus.swift
//  MVK++ Phone App
//

import Foundation

/// „Elérem?” — can I walk to the stop before the bus gets there. A port of
/// the core `catchBus` and the web app's `useCatch`.
///
/// The bus can come earlier than expected, but the early side is much
/// narrower than the late one, so "earliest" is the expected time minus a
/// share of the upper (85th percentile) spread, between half a minute and two.
enum CatchBus {
    static let walkMps = 1.3
    static let runMps = 2.7
    static let detour = 1.3
    static let earlyShare = 0.35
    static let earlyMinS = 30.0
    static let earlyMaxS = 120.0
    static let earlyDefaultS = 45.0
    static let safetyS = 30.0
    static let goWindowS = 90.0
    /// Beyond about 25 minutes on foot walking is not the question.
    static let maxWalkM = 1500.0

    enum State { case relax, go, run, missed }

    struct Verdict: Equatable {
        let state: State
        let walkS: Double
        let runS: Double
        let earliestUnix: Double
        let leaveAtUnix: Double
        let slackS: Double
    }

    static func walkSeconds(distanceM: Double) -> Double {
        (max(0, distanceM) * detour / walkMps).rounded()
    }

    static func earlySpread(expected: Double, upper: Double?) -> Double {
        guard let upper, upper.isFinite else { return earlyDefaultS }
        return min(earlyMaxS, max(earlyMinS, max(0, upper - expected) * earlyShare)).rounded()
    }

    static func verdict(now: Double, expected: Double, upper: Double?, walkS: Double) -> Verdict {
        let earliest = expected - earlySpread(expected: expected, upper: upper)
        let leaveAt = earliest - walkS - safetyS
        let slack = (leaveAt - now).rounded()
        let runS = (walkS * walkMps / runMps).rounded()
        let state: State
        if slack > goWindowS {
            state = .relax
        } else if now + walkS <= expected {
            state = .go
        } else if now + runS <= expected {
            state = .run
        } else {
            state = .missed
        }
        return Verdict(state: state, walkS: walkS, runS: runS, earliestUnix: earliest, leaveAtUnix: leaveAt, slackS: slack)
    }

    /// When the bus is expected at the stop (unix) and its 85% upper bound.
    /// At the first stop of a run there is no segment forecast: the late-start
    /// prediction is what counts there.
    static func expectedArrival(_ arrival: ArrivalItem, now: Double) -> (at: Double, upper: Double?) {
        guard let sched = arrival.schedUnix else { return (now + Double(arrival.etaMin * 60), nil) }
        let delay = arrival.forecastDelaySec.map(Double.init)
            ?? arrival.startRisk?.expectedDelayS
            ?? (arrival.delaySec ?? arrival.measuredDelaySec).map(Double.init)
            ?? 0
        let upper = arrival.forecastUpperSec.map { sched + Double($0) }
        return (sched + delay, upper)
    }
}

/// The verdicts for one stop's departures, from where the rider is now.
struct CatchFor {
    /// Walk to the stop (s), when the rider is located and within walking range.
    let walkS: Double?
    let now: Double

    init(stopLat: Double?, stopLon: Double?, position: GeoPosition?, now: Double) {
        self.now = now
        guard let position, let stopLat, let stopLon else {
            walkS = nil
            return
        }
        let distM = Geo.distanceKm(position.lat, position.lon, stopLat, stopLon) * 1000
        walkS = distM <= CatchBus.maxWalkM ? CatchBus.walkSeconds(distanceM: distM) : nil
    }

    func verdict(_ arrival: ArrivalItem) -> CatchBus.Verdict? {
        guard let walkS, !arrival.isCancelled else { return nil }
        let expected = CatchBus.expectedArrival(arrival, now: now)
        return CatchBus.verdict(now: now, expected: expected.at, upper: expected.upper, walkS: walkS)
    }
}
