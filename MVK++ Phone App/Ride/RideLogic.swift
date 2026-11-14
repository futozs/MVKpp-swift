//
//  RideLogic.swift
//  MVK++ Phone App
//
//  Port of `@mvk/core/rides`, `@mvk/core/rideStats` and the turn decision of
//  `@mvk/core/loops`: where the rider got on and off, the trip's measured
//  stop times, and the ride log's statistics.
//

import Foundation

/// One stop of a trip (`/engine/trip` → `stops`).
struct TripStop: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let lat: Double?
    let lon: Double?
    let dep: Int?
    let schedTime: String
    /// Scheduled departure (unix).
    let schedTs: Double
    let idx: Int

    var stableId: Int { idx }
}

/// One stop event of a trip (`/engine/trip` → `events`).
struct RideStopEvent: Decodable, Hashable {
    let stop_idx: Int
    let arr: Double
    let dep: Double?
    let delay_s: Double
}

struct RideStopTime: Hashable {
    let arr: Double
    let dep: Double?
    let delayS: Double
}

struct ForecastStop: Decodable, Hashable {
    let idx: Int
    let stopId: String
    let schedS: Double
    let delayS: Double
    let upperS: Double
}

struct RideTripForecast: Decodable, Hashable {
    let stops: [ForecastStop]
}

/// The run of a trip as the server saw it.
struct TripRun: Decodable, Hashable {
    let serviceDate: String?
    let vehicleId: String?
    let status: String?
    let lastStopIdx: Int?
    let lastDelayS: Double?
    let stopsTotal: Int?
    let closeReason: String?
    /// Arrival at the terminus (unix).
    let actualEnd: Double?
}

/// `/engine/trip?trip=&date=`.
struct TripDetailResponse: Decodable {
    let stops: [TripStop]?
    let loopEnd: Bool?
    let tripShort: String?
    let run: TripRun?
    let liveDelaySec: Double?
    let forecast: RideTripForecast?
    let events: [RideStopEvent]?
}

/// The vehicle on a trip push.
struct TripLiveVehicle: Decodable, Hashable {
    let id: String
    let lat: Double
    let lon: Double
    let speed: Double?
}

enum RideLogic {
    /// How far the bus (or the phone) may be from a stop and still stand at it (m).
    static let atStopM: Double = 70
    private static let boardNearM: Double = 400
    private static let alightNearM: Double = 500
    private static let preferLaterM: Double = 25

    /// Flat-earth distance for short hops (m), as core `fastDistM`.
    static func fastDistM(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let kx = 111_320 * cos(48.1 * .pi / 180)
        let ky = 111_320.0
        return hypot((bLon - aLon) * kx, (bLat - aLat) * ky)
    }

    /// Great-circle distance (m).
    static func distM(_ a: RidePoint, _ b: RidePoint) -> Double {
        Geo.distanceKm(a.lat, a.lon, b.lat, b.lon) * 1000
    }

    private static func dist(_ p: RidePoint, _ s: TripStop) -> Double {
        guard let lat = s.lat, let lon = s.lon else { return .infinity }
        return fastDistM(p.lat, p.lon, lat, lon)
    }

    /// Where the bus is now: the last stop it left, or the next if `at` is already there.
    static func currentStopIdx(_ stops: [TripStop], passed: Int, at: RidePoint?, atStopM: Double = atStopM) -> Int {
        guard !stops.isEmpty else { return 0 }
        let nextIdx = passed + 1
        if let at, nextIdx >= 0, nextIdx < stops.count, dist(at, stops[nextIdx]) <= atStopM { return nextIdx }
        return max(0, min(passed, stops.count - 1))
    }

    private static func nearestIdx(_ stops: [TripStop], from: Int, to: Int, _ p: RidePoint, maxM: Double) -> Int? {
        var best: Int?
        var bestD = Double.infinity
        let hi = min(to, stops.count - 1)
        let lo = max(0, from)
        guard hi >= lo else { return nil }
        for i in stride(from: hi, through: lo, by: -1) {
            let d = dist(p, stops[i])
            if d < bestD - (best == nil ? 0 : preferLaterM) {
                best = i
                bestD = d
            }
        }
        return best != nil && bestD <= maxM ? best : nil
    }

    static func guessBoardIdx(_ stops: [TripStop], passed: Int, phone: RidePoint?, bus: RidePoint?) -> Int {
        let lastBoardable = max(0, stops.count - 2)
        let cur = min(currentStopIdx(stops, passed: passed, at: phone ?? bus), lastBoardable)
        guard let phone else { return cur }
        return nearestIdx(stops, from: 0, to: cur, phone, maxM: boardNearM) ?? cur
    }

    static func guessAlightIdx(_ stops: [TripStop], fromIdx: Int, passed: Int, phone: RidePoint?, lastWithBusIdx: Int?) -> Int {
        let last = stops.count - 1
        let lo = min(last, max(fromIdx + 1, lastWithBusIdx ?? 0))
        let hi = max(lo, min(passed, last))
        if let phone, let near = nearestIdx(stops, from: lo, to: hi, phone, maxM: alightNearM) { return near }
        return lastWithBusIdx != nil ? lo : hi
    }

    /// The trip's events by stop (the first event counts if a stop appears twice).
    static func stopTimes(_ events: [RideStopEvent]) -> [Int: RideStopTime] {
        var out: [Int: RideStopTime] = [:]
        for e in events where out[e.stop_idx] == nil {
            out[e.stop_idx] = RideStopTime(arr: e.arr, dep: e.dep, delayS: e.delay_s)
        }
        return out
    }

    /// Stop to stop in straight lines (m).
    static func pathLengthM(_ stops: [TripStop], from: Int, to: Int) -> Double? {
        var sum = 0.0
        let lo = max(0, from)
        let hi = min(to, stops.count - 1)
        guard lo < hi else { return 0 }
        for i in lo..<hi {
            guard let aLat = stops[i].lat, let aLon = stops[i].lon,
                  let bLat = stops[i + 1].lat, let bLon = stops[i + 1].lon else { return nil }
            sum += Geo.distanceKm(aLat, aLon, bLat, bLon) * 1000
        }
        return sum.rounded()
    }

    /// A saved ride's boarding and alighting indices; on a circular route the
    /// same stop appears twice, alighting is the first after boarding.
    static func rideStopIdx(_ stops: [TripStop], fromStopId: String?, toStopId: String?) -> (from: Int?, to: Int?) {
        let from = fromStopId.flatMap { id in stops.firstIndex { $0.id == id } }
        let to = toStopId.flatMap { id in
            stops.indices.first { $0 > (from ?? -1) && stops[$0].id == id }
        }
        return (from, to)
    }

    struct BoardFields {
        let fromStopId: String
        let fromStopName: String
        let boardedAt: Double
        let delayAtBoardS: Double?
    }

    struct AlightFields {
        let toStopId: String
        let toStopName: String
        let alightedAt: Double
        let delayAtAlightS: Double?
    }

    /// A fallback when the trip has no event at the stop: a known time (nil:
    /// timetable + delay) and the delay.
    struct StopFallback {
        let at: Double?
        let delayS: Double?
    }

    private static func fallbackTs(_ s: TripStop, _ f: StopFallback) -> Double {
        f.at ?? s.schedTs + (f.delayS ?? 0)
    }

    static func boardAt(_ stops: [TripStop], _ times: [Int: RideStopTime], _ idx: Int, _ fallback: StopFallback) -> BoardFields? {
        guard stops.indices.contains(idx) else { return nil }
        let s = stops[idx]
        let t = times[idx]
        return BoardFields(
            fromStopId: s.id,
            fromStopName: s.name,
            boardedAt: t.map { $0.dep ?? $0.arr } ?? fallbackTs(s, fallback),
            delayAtBoardS: t.map(\.delayS) ?? fallback.delayS
        )
    }

    static func alightAt(_ stops: [TripStop], _ times: [Int: RideStopTime], _ idx: Int, _ fallback: StopFallback) -> AlightFields? {
        guard stops.indices.contains(idx) else { return nil }
        let s = stops[idx]
        let t = times[idx]
        return AlightFields(
            toStopId: s.id,
            toStopName: s.name,
            alightedAt: t?.arr ?? fallbackTs(s, fallback),
            delayAtAlightS: t.map(\.delayS) ?? fallback.delayS
        )
    }

    /// The delay at a stop without its own event: the nearest measured stop's.
    static func nearestDelayS(_ times: [Int: RideStopTime], _ idx: Int) -> Double? {
        let best = times.min { a, b in
            let ga = abs(a.key - idx), gb = abs(b.key - idx)
            if ga != gb { return ga < gb }
            return a.key > b.key
        }
        return best?.value.delayS
    }

    static func estimatedAt(_ stops: [TripStop], _ times: [Int: RideStopTime], _ idx: Int) -> Double? {
        guard stops.indices.contains(idx) else { return nil }
        return stops[idx].schedTs + (nearestDelayS(times, idx) ?? 0)
    }

    // MARK: - Loop turn

    enum TurnDecision { case wait, alight, `continue` }

    /// If the next trip is not known within this long, the journey ended at the terminus (s).
    static let turnFindS: Double = 20 * 60
    /// If the next trip has not left within this long, the journey ended at the terminus (s).
    static let turnDepartS: Double = 45 * 60

    static func plannedTurnDecision(arrivedAt: Double, cont: Continuation?, now: Double) -> TurnDecision {
        guard let cont else { return .wait }
        if let next = cont.next, next.kind != nil, !next.cancelled {
            if next.departed { return .continue }
            return now - arrivedAt > turnDepartS ? .alight : .wait
        }
        return now - arrivedAt > turnFindS ? .alight : .wait
    }
}

// MARK: - Statistics

struct JourneyDelay {
    let boardS: Double?
    let alightS: Double?
    /// How much longer the journey took than timetabled (≥ 0).
    let extraS: Double?

    init(_ legs: [Ride]) {
        boardS = legs.first?.delayAtBoardS
        alightS = legs.last?.delayAtAlightS
        if let b = boardS, let a = alightS { extraS = max(0, a - b) } else { extraS = nil }
    }
}

struct RideStats {
    struct StopCount: Identifiable {
        let id: String
        let name: String
        let n: Int
    }

    struct RouteCount: Identifiable {
        let route: String
        let color: String
        let text: String
        let n: Int
        let avgDelayS: Double?
        var id: String { route }
    }

    struct PairCount: Identifiable {
        let from: String
        let to: String
        let n: Int
        var id: String { "\(from)\u{0}\(to)" }
    }

    struct Record {
        let legs: [Ride]
        let value: Double
    }

    /// Within ±1 minute counts as on time.
    static let onTimeS: Double = 60

    var journeys = 0
    var loops = 0
    var km = 0.0
    var minutes = 0
    var vehicles: [(String, Int)] = []
    var routes: [RouteCount] = []
    var onTimePct: Int?
    var extraOnboardS = 0.0
    var lateWaitS = 0.0
    var delayMeasured = 0
    var boardStops: [StopCount] = []
    var alightStops: [StopCount] = []
    var stopsCollected: [StopCount] = []
    var pairs: [PairCount] = []
    var hours = Array(repeating: 0, count: 24)
    var weekdays = Array(repeating: 0, count: 7)
    var longest: Record?
    var mostDelayed: Record?
    var longestTime: Record?

    private static var budapest: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        return calendar
    }

    init(journeys groups: [[Ride]]) {
        var vehicleCounts: [String: Int] = [:]
        var routeAcc: [String: (sample: Ride, n: Int, sum: Double, count: Int)] = [:]
        var board: [String: StopCount] = [:]
        var alight: [String: StopCount] = [:]
        var collected: [String: StopCount] = [:]
        var pairMap: [String: PairCount] = [:]
        var meters = 0.0
        var measured = 0
        var onTime = 0
        let calendar = Self.budapest

        func bump(_ m: inout [String: StopCount], _ id: String?, _ name: String?) {
            guard id != nil || name != nil else { return }
            let key = name ?? id ?? ""
            let cur = m[key]
            m[key] = StopCount(id: cur?.id ?? id ?? key, name: name ?? id ?? key, n: (cur?.n ?? 0) + 1)
        }

        func better(_ cur: Record?, _ legs: [Ride], _ value: Double?) -> Record? {
            guard let value, value > 0 else { return cur }
            guard let cur else { return Record(legs: legs, value: value) }
            return value > cur.value ? Record(legs: legs, value: value) : cur
        }

        for legs in groups {
            guard let first = legs.first, let last = legs.last else { continue }
            journeys += 1
            if legs.count > 1 { loops += 1 }
            var jm = 0.0
            for r in legs {
                if !r.vehicleId.isEmpty { vehicleCounts[r.vehicleId, default: 0] += 1 }
                var acc = routeAcc[r.route] ?? (r, 0, 0, 0)
                acc.n += 1
                if let d = r.delayAtBoardS {
                    acc.sum += d
                    acc.count += 1
                }
                routeAcc[r.route] = acc
                jm += r.distanceM ?? 0
            }
            meters += jm
            let jmin = last.alightedAt.map { max(0, Int((($0 - first.boardedAt) / 60).rounded())) }
            if let jmin { minutes += jmin }

            let d = JourneyDelay(legs)
            if let b = d.boardS {
                measured += 1
                if abs(b) <= Self.onTimeS { onTime += 1 }
                lateWaitS += max(0, b)
            }
            if let e = d.extraS {
                delayMeasured += 1
                extraOnboardS += e
            }

            bump(&board, first.fromStopId, first.fromStopName)
            bump(&alight, last.toStopId, last.toStopName)
            bump(&collected, first.fromStopId, first.fromStopName)
            bump(&collected, last.toStopId, last.toStopName)
            if let from = first.fromStopName, let to = last.toStopName {
                let key = "\(from)\u{0}\(to)"
                pairMap[key] = PairCount(from: from, to: to, n: (pairMap[key]?.n ?? 0) + 1)
            }
            let at = Date(timeIntervalSince1970: first.boardedAt)
            hours[calendar.component(.hour, from: at) % 24] += 1
            let weekday = calendar.component(.weekday, from: at)
            weekdays[(weekday + 5) % 7] += 1

            longest = better(longest, legs, jm > 0 ? jm : nil)
            mostDelayed = better(mostDelayed, legs, d.extraS)
            longestTime = better(longestTime, legs, jmin.map(Double.init))
        }

        let hu = Locale(identifier: "hu_HU")
        let byCountThenName: (StopCount, StopCount) -> Bool = {
            $0.n != $1.n ? $0.n > $1.n : $0.name.compare($1.name, locale: hu) == .orderedAscending
        }
        km = meters / 1000
        vehicles = vehicleCounts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.compare($1.key, options: .numeric, locale: hu) == .orderedAscending
        }.map { ($0.key, $0.value) }
        routes = routeAcc.map { route, v in
            RouteCount(route: route, color: v.sample.color, text: v.sample.text, n: v.n, avgDelayS: v.count > 0 ? (v.sum / Double(v.count)).rounded() : nil)
        }.sorted {
            $0.n != $1.n ? $0.n > $1.n : $0.route.compare($1.route, options: .numeric, locale: hu) == .orderedAscending
        }
        onTimePct = measured > 0 ? Int((100 * Double(onTime) / Double(measured)).rounded()) : nil
        boardStops = board.values.sorted(by: byCountThenName)
        alightStops = alight.values.sorted(by: byCountThenName)
        stopsCollected = collected.values.sorted(by: byCountThenName)
        pairs = pairMap.values.sorted { $0.n > $1.n }
    }
}
