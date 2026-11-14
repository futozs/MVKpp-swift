//
//  MapHistory.swift
//  MVK++ Phone App
//
//  The timeline's data: `historyData.ts`, `historySampler.ts`,
//  `historyTime.ts` and `useHistoryFrames.ts`.
//

import Combine
import CoreLocation
import Foundation

/// One vehicle's track within a window, in time order.
struct MapHistoryTrack {
    let id: String
    let route: String?
    let trip: String?
    let ts: [Double]
    let lat: [Double]
    let lon: [Double]
    /// NaN when the fix carried no heading.
    let brg: [Double]
    /// Per point: index into `routes` (−1: the vehicle ran no trip then).
    let routeIdx: [Int]
    let routes: [String]

    /// The route at a point; the old payload's single route otherwise.
    func routeAt(_ i: Int) -> String? {
        guard !routes.isEmpty else { return route }
        let ri = i >= 0 && i < routeIdx.count ? routeIdx[i] : -1
        return ri >= 0 && ri < routes.count ? routes[ri] : nil
    }
}

struct MapHistoryWindow {
    let start: Double
    let end: Double
    let tracks: [String: MapHistoryTrack]
}

enum MapHistoryData {
    /// The backend answers at most this much at once (s).
    static let windowSec: Double = 2 * 3600

    static func windowStart(of t: Double) -> Double {
        (t / windowSec).rounded(.down) * windowSec
    }

    private static func isDay(_ value: Any?) -> String? {
        guard let s = value as? String, s.count == 10, s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return s
    }

    private static func text(_ value: Any?) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func json(_ path: String, _ query: [URLQueryItem] = []) async throws -> Any {
        let data = try await APIClient.shared.rawData(path: path, queryItems: query)
        return try JSONSerialization.jsonObject(with: data)
    }

    /// The first and last day with raw GPS (`yyyy-MM-dd`), or nil.
    static func days() async throws -> (min: String, max: String)? {
        let raw = try await json("/engine/history/days") as? [String: Any]
        let gps = raw?["gps"] as? [String: Any]
        guard let mn = isDay(gps?["mn"]), let mx = isDay(gps?["mx"]), mn <= mx else { return nil }
        return (mn, mx)
    }

    static func window(start: Double) async throws -> MapHistoryWindow {
        let end = start + windowSec
        let raw = try await json("/engine/history/frames", [
            URLQueryItem(name: "from", value: String(Int(start))),
            URLQueryItem(name: "to", value: String(Int(end))),
            URLQueryItem(name: "modes", value: TransitMode.param()),
        ]) as? [String: Any]
        let vehicles = raw?["vehicles"] as? [String: Any] ?? [:]
        var tracks: [String: MapHistoryTrack] = [:]
        for (id, value) in vehicles {
            if let track = parse(id, value) { tracks[id] = track }
        }
        return MapHistoryWindow(start: start, end: end, tracks: tracks)
    }

    private static func parse(_ id: String, _ raw: Any) -> MapHistoryTrack? {
        guard let object = raw as? [String: Any], let pts = object["p"] as? [Any] else { return nil }
        let routes = (object["routes"] as? [Any])?.map { text($0) ?? "?" } ?? []
        var rows: [(t: Double, la: Double, lo: Double, b: Double, ri: Int)] = []
        rows.reserveCapacity(pts.count)
        for p in pts {
            guard let a = p as? [Any], a.count >= 3,
                  let t = (a[0] as? NSNumber)?.doubleValue, let la = (a[1] as? NSNumber)?.doubleValue,
                  let lo = (a[2] as? NSNumber)?.doubleValue, t.isFinite, la.isFinite, lo.isFinite
            else { continue }
            let b = a.count > 3 ? ((a[3] as? NSNumber)?.doubleValue ?? .nan) : .nan
            let riRaw = a.count > 4 ? (a[4] as? NSNumber)?.intValue : nil
            let ri = riRaw.flatMap { $0 >= 0 && $0 < routes.count ? $0 : nil } ?? -1
            rows.append((t, la, lo, b.isFinite ? b : .nan, ri))
        }
        guard !rows.isEmpty else { return nil }
        if zip(rows, rows.dropFirst()).contains(where: { $0.t > $1.t }) {
            rows.sort { $0.t < $1.t }
        }
        return MapHistoryTrack(
            id: id,
            route: text(object["route"]),
            trip: text(object["trip"]),
            ts: rows.map(\.t), lat: rows.map(\.la), lon: rows.map(\.lo), brg: rows.map(\.b), routeIdx: rows.map(\.ri),
            routes: routes
        )
    }
}

// MARK: - Sampling

enum MapHistorySampler {
    /// Beyond a gap this long no interpolation: the vehicle is not shown.
    static let maxGapSec: Double = 180
    private static let holdAfterFixSec: Double = 45
    private static let showBeforeFixSec: Double = 15
    private static let minMoveM: Double = 5

    struct PointRef {
        let track: MapHistoryTrack
        let i: Int
        var t: Double { track.ts[i] }
        var lat: Double { track.lat[i] }
        var lon: Double { track.lon[i] }
    }

    struct Sample {
        let lat: Double
        let lon: Double
        let index: Int
        let fixTs: Double
        let a: PointRef?
        let b: PointRef?
    }

    /// The largest `i` with `ts[i] <= t`; -1 if none. O(1) while playing.
    static func seek(_ ts: [Double], _ t: Double, hint: Int) -> Int {
        let n = ts.count
        if hint >= 0, hint < n, ts[hint] <= t {
            if hint == n - 1 || ts[hint + 1] > t { return hint }
            if hint + 2 >= n || ts[hint + 2] > t { return hint + 1 }
        }
        var lo = 0, hi = n - 1, ans = -1
        while lo <= hi {
            let mid = (lo + hi) >> 1
            if ts[mid] <= t {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ans
    }

    static func sample(_ track: MapHistoryTrack, _ t: Double, hint: Int, prev: MapHistoryTrack?, next: MapHistoryTrack?) -> Sample? {
        let n = track.ts.count
        let index = seek(track.ts, t, hint: hint)
        let a: PointRef? = index >= 0 ? PointRef(track: track, i: index)
            : prev.flatMap { $0.ts.isEmpty ? nil : PointRef(track: $0, i: $0.ts.count - 1) }
        let b: PointRef? = index + 1 < n ? PointRef(track: track, i: index + 1)
            : next.flatMap { $0.ts.isEmpty ? nil : PointRef(track: $0, i: 0) }
        let ta = a?.t ?? -.infinity
        let tb = b?.t ?? .infinity
        if let a, let b, tb - ta <= maxGapSec {
            let f = tb > ta ? min(1, max(0, (t - ta) / (tb - ta))) : 0
            return Sample(lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f, index: index, fixTs: ta, a: a, b: b)
        }
        if let a, t - ta <= holdAfterFixSec {
            return Sample(lat: a.lat, lon: a.lon, index: index, fixTs: ta, a: a, b: nil)
        }
        if let b, tb - t <= showBeforeFixSec {
            return Sample(lat: b.lat, lon: b.lon, index: index, fixTs: tb, a: nil, b: b)
        }
        return nil
    }

    private static func distanceM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let deg = Double.pi / 180
        let x = (lon2 - lon1) * deg * cos((lat1 + lat2) / 2 * deg)
        let y = (lat2 - lat1) * deg
        return sqrt(x * x + y * y) * 6_371_000
    }

    private static func bearingDeg(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let deg = Double.pi / 180
        let p1 = lat1 * deg, p2 = lat2 * deg, dl = (lon2 - lon1) * deg
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(y, x) / deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Heading and speed for the popup.
    static func motion(_ s: Sample) -> (bearing: Double?, speedKmh: Double?) {
        var bearing: Double?
        var speed: Double?
        if let a = s.a, let b = s.b {
            let dist = distanceM(a.lat, a.lon, b.lat, b.lon)
            let dt = b.t - a.t
            if dt > 0 { speed = dist / dt * 3.6 }
            if dist >= minMoveM { bearing = bearingDeg(a.lat, a.lon, b.lat, b.lon) }
        }
        if bearing == nil {
            let own = s.a.map { $0.track.brg[$0.i] } ?? s.b.map { $0.track.brg[$0.i] } ?? .nan
            if own.isFinite { bearing = own }
        }
        return (bearing, speed)
    }

    private static let compass = ["É", "ÉK", "K", "DK", "D", "DNy", "Ny", "ÉNy"]

    static func compassLabel(_ deg: Double) -> String {
        let normalized = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return compass[Int((normalized / 45).rounded()) % 8]
    }
}

// MARK: - Time

/// Everything in Europe/Budapest; the service day runs 03:00–03:00.
enum MapHistoryTime {
    static let timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
    static let serviceDayStartHour = 3

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }

    private static let clockFmt = formatter("HH:mm:ss")
    private static let clockShortFmt = formatter("HH:mm")
    private static let hourFmt = formatter("HH")
    private static let dayLong: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("MMMdEEEE")
        return f
    }()
    private static let dayShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return f
    }()

    /// Budapest wall clock (day + hour) → unix seconds, DST included.
    static func zonedUnix(_ day: String, hour: Int) -> Double {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let date = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour)) else { return 0 }
        return date.timeIntervalSince1970
    }

    static func addDays(_ day: String, _ delta: Int) -> String {
        ServiceClock.shiftIso(day, by: delta)
    }

    struct DayRange: Equatable {
        let day: String
        let start: Double
        let end: Double
    }

    static func serviceDayRange(_ day: String) -> DayRange {
        DayRange(day: day, start: zonedUnix(day, hour: serviceDayStartHour), end: zonedUnix(addDays(day, 1), hour: serviceDayStartHour))
    }

    static func serviceDay(of unix: Double) -> String {
        ServiceClock.at(Int(unix)).iso
    }

    static func daysBetweenDesc(_ min: String, _ max: String) -> [String] {
        var out: [String] = []
        var day = max
        var guardCount = 0
        while guardCount < 400, day >= min {
            out.append(day)
            day = addDays(day, -1)
            guardCount += 1
        }
        return out
    }

    static func clock(_ unix: Double) -> String { clockFmt.string(from: Date(timeIntervalSince1970: unix)) }
    static func clockShort(_ unix: Double) -> String { clockShortFmt.string(from: Date(timeIntervalSince1970: unix)) }

    /// „okt. 20., kedd” (short: „okt. 20., K”) — at noon so DST cannot shift it.
    static func dayLabel(_ day: String, short: Bool = false) -> String {
        (short ? dayShort : dayLong).string(from: Date(timeIntervalSince1970: zonedUnix(day, hour: 12)))
    }

    static func dateOf(_ unix: Double) -> String {
        dayLong.string(from: Date(timeIntervalSince1970: unix))
    }

    struct HourTick: Identifiable {
        let t: Double
        let label: String
        var id: Double { t }
    }

    static func hourTicks(_ range: DayRange) -> [HourTick] {
        var ticks: [HourTick] = []
        var t = range.start
        while t <= range.end {
            ticks.append(HourTick(t: t, label: hourFmt.string(from: Date(timeIntervalSince1970: t))))
            t += 3600
        }
        return ticks
    }
}

// MARK: - Frames cache

/// On-demand, cached two-hour GPS windows. `ensure` asks for the windows
/// around the cursor; what is no longer wanted is cancelled.
@MainActor
final class MapHistoryFrames: ObservableObject {
    @Published private(set) var version = 0
    @Published private(set) var pending: [Double] = []
    @Published private(set) var error: String?

    private struct Entry {
        let window: MapHistoryWindow
        let fetchedAt: Date
        let complete: Bool
    }

    private struct Failure {
        let at: Date
        let count: Int
    }

    private static let maxCached = 8
    private static let partialTTL: TimeInterval = 60
    private static let completeGrace: Double = 180

    private var cache: [Double: Entry] = [:]
    private var order: [Double] = []
    private var inflight: [Double: Task<Void, Never>] = [:]
    private var failed: [Double: Failure] = [:]

    private static func retryDelay(_ count: Int) -> TimeInterval {
        min(30, 2 * pow(2, Double(max(0, count - 1))))
    }

    func get(_ start: Double) -> MapHistoryWindow? { cache[start]?.window }

    private func touch(_ start: Double) {
        order.removeAll { $0 == start }
        order.append(start)
    }

    private func evict(keep: Set<Double>) {
        for start in order where cache.count > Self.maxCached && !keep.contains(start) {
            cache[start] = nil
            order.removeAll { $0 == start }
        }
    }

    private func sync(error: String?? = nil) {
        version += 1
        pending = Array(inflight.keys)
        if let error { self.error = error }
    }

    func ensure(_ starts: [Double]) {
        let wanted = Set(starts)
        var changed = false
        for (start, task) in inflight where !wanted.contains(start) {
            task.cancel()
            inflight[start] = nil
            changed = true
        }
        let now = Date()
        for start in wanted {
            if let entry = cache[start] {
                touch(start)
                if entry.complete || now.timeIntervalSince(entry.fetchedAt) < Self.partialTTL { continue }
            }
            if inflight[start] != nil { continue }
            if let f = failed[start], now.timeIntervalSince(f.at) < Self.retryDelay(f.count) { continue }
            load(start, wanted: wanted)
            changed = true
        }
        if changed { sync() }
    }

    private func load(_ start: Double, wanted: Set<Double>) {
        inflight[start] = Task { [weak self] in
            do {
                let window = try await MapHistoryData.window(start: start)
                guard let self, !Task.isCancelled else { return }
                self.inflight[start] = nil
                self.failed[start] = nil
                self.cache[start] = Entry(
                    window: window,
                    fetchedAt: Date(),
                    complete: window.end + Self.completeGrace < RealtimeClient.shared.serverNow
                )
                self.touch(start)
                self.evict(keep: wanted)
                self.sync(error: .some(nil))
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.inflight[start] = nil
                let count = (self.failed[start]?.count ?? 0) + 1
                self.failed[start] = Failure(at: Date(), count: count)
                self.sync(error: .some("Nem sikerült betölteni az előzményt. \(error.localizedDescription)"))
                try? await Task.sleep(for: .seconds(Self.retryDelay(count) + 0.05))
                self.sync()
            }
        }
    }

    func retry() {
        failed = [:]
        sync(error: .some(nil))
    }

    func cancelAll() {
        inflight.values.forEach { $0.cancel() }
        inflight = [:]
    }
}

/// The recorded GPS days, fetched once per session (refreshed after 10 min).
@MainActor
final class MapHistoryDays: ObservableObject {
    @Published private(set) var days: [String]?
    @Published private(set) var error: String?

    private static var cached: (at: Date, value: (min: String, max: String)?)?

    func load() async {
        error = nil
        if let cached = Self.cached, Date().timeIntervalSince(cached.at) < 600 {
            apply(cached.value)
            return
        }
        do {
            let value = try await MapHistoryData.days()
            Self.cached = (Date(), value)
            apply(value)
        } catch {
            Self.cached = nil
            self.error = "Az előzmények most nem érhetők el. \(error.localizedDescription)"
        }
    }

    private func apply(_ value: (min: String, max: String)?) {
        days = value.map { MapHistoryTime.daysBetweenDesc($0.min, $0.max) } ?? []
    }
}
