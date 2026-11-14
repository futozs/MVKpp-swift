//
//  LiveMotion.swift
//  MVK++ Phone App
//
//  Port of the web app's `map/liveMotion.ts`, `map/motionFollow.ts` and
//  `map/onboard.ts`: between two GPS pushes a vehicle travels along the
//  server's expected path (`LiveMotion.k`) and never reverses; the vehicle the
//  rider is sitting on follows the phone's own GPS instead.
//

import CoreLocation
import Foundation

/// A shape's points and the cumulative length up to each point (m), straight
/// from `/gtfs/shape?id=` — the same projection the server's `along` values use.
struct ShapeLine: Decodable {
    let id: String?
    let pts: [[Double]]
    let cum: [Double]
}

/// Where a marker was last drawn on its shape, its speed (m/s) and when.
struct ShownMotion: Equatable {
    var shape: String
    var along: Double
    var u: Double?
    var at: Double?
}

/// A path to follow: shape id, fix time and `[along m, seconds since fix]` keys.
struct MotionPath {
    let s: String
    let t: Double
    let k: [[Double]]
}

enum MotionFollow {
    /// After the path's last key the vehicle stays put (s).
    static let maxPathS: Double = 90

    struct Params {
        /// A lag disappears in this long (s).
        let catchS: Double
        /// A lead runs out in this long, the marker slowing or holding meanwhile (s).
        let holdS: Double
        let maxSpeed: Double
        /// Beyond this error the marker jumps instead of following (m).
        let snapM: Double
        /// After a drawing gap longer than this it no longer glides (s).
        let maxStepS: Double
    }

    static let follow = Params(catchS: 1.2, holdS: 1.5, maxSpeed: 25, snapM: 400, maxStepS: 5)

    /// Where the path is at `now` (server time, s).
    static func pathAt(_ m: MotionPath, _ now: Double) -> Double {
        let k = m.k
        guard let first = k.first, first.count >= 2 else { return 0 }
        let dt = min(maxPathS, now - m.t)
        if dt <= first[1] { return first[0] }
        for i in 1..<k.count where k[i].count >= 2 && dt <= k[i][1] {
            let a0 = k[i - 1][0], t0 = k[i - 1][1], a1 = k[i][0], t1 = k[i][1]
            return t1 > t0 ? a0 + (a1 - a0) * (dt - t0) / (t1 - t0) : a1
        }
        return k[k.count - 1][0]
    }

    /// The marker's next place; `shown` is the previous drawing.
    static func followPath(_ m: MotionPath, _ now: Double, _ shown: ShownMotion?, _ p: Params = follow) -> ShownMotion {
        let target = pathAt(m, now)
        let vPath = max(0, pathAt(m, now + 0.5) - pathAt(m, now - 0.5))
        guard let shown, shown.shape == m.s, abs(target - shown.along) <= p.snapM else {
            return ShownMotion(shape: m.s, along: target, u: vPath, at: now)
        }
        let step = shown.at.map { now - $0 } ?? .infinity
        if step <= 0 {
            var same = shown
            same.at = now
            return same
        }
        if step > p.maxStepS {
            return ShownMotion(shape: m.s, along: max(shown.along, target), u: vPath, at: now)
        }
        let gap = target - shown.along
        if gap >= 0 {
            let u = min(p.maxSpeed, vPath + gap / p.catchS)
            return ShownMotion(shape: m.s, along: min(target, shown.along + u * step), u: u, at: now)
        }
        let lead = shown.along - pathAt(m, now - step)
        let u = max(0, vPath - max(0, lead) / p.holdS)
        return ShownMotion(shape: m.s, along: shown.along + u * step, u: u, at: now)
    }
}

enum Onboard {
    private static let gpsMaxAgeS: Double = 6
    private static let gpsMaxAccuracyM: Double = 40
    private static let offRouteM: Double = 45
    private static let behindFixM: Double = 40
    private static let aheadMaxSpeed: Double = 25
    private static let aheadSlackM: Double = 80
    private static let searchM: Double = 600
    private static let alongPenalty: Double = 0.1
    private static let extrapolateS: Double = 2
    private static let mPerDegLat: Double = 110_540
    private static let mPerDegLon: Double = 111_320

    private static func firstAtOrAfter(_ cum: [Double], _ along: Double) -> Int {
        var lo = 0
        var hi = cum.count - 1
        while lo < hi {
            let mid = (lo + hi) >> 1
            if cum[mid] < along { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The point's projection near `near` on the shape; on a loop the stretch
    /// closer to the expected place wins.
    static func projectOnShape(_ shape: ShapeLine, lat: Double, lon: Double, near: Double) -> (along: Double, dist: Double)? {
        let pts = shape.pts, cum = shape.cum
        guard pts.count >= 2, cum.count == pts.count else { return nil }
        let kx = mPerDegLon * cos(lat * .pi / 180)
        let from = max(0, firstAtOrAfter(cum, near - searchM) - 1)
        let to = min(pts.count - 1, firstAtOrAfter(cum, near + searchM) + 1)
        var best: (along: Double, dist: Double)?
        var bestScore = Double.infinity
        guard from < to else { return nil }
        for i in from..<to {
            let ax = (pts[i][1] - lon) * kx
            let ay = (pts[i][0] - lat) * mPerDegLat
            let bx = (pts[i + 1][1] - lon) * kx
            let by = (pts[i + 1][0] - lat) * mPerDegLat
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let f = len2 > 0 ? min(1, max(0, -(ax * dx + ay * dy) / len2)) : 0
            let dist = hypot(ax + f * dx, ay + f * dy)
            let along = cum[i] + f * (cum[i + 1] - cum[i])
            let score = dist + alongPenalty * abs(along - near)
            if score < bestScore {
                bestScore = score
                best = (along, dist)
            }
        }
        return best
    }

    /// A path for the ridden vehicle's marker from the phone's position, or
    /// nil when the phone is not the more accurate source right now.
    static func onboardPath(_ gps: GeoPosition, shape: ShapeLine, motion m: LiveMotion, near: Double, nowServer: Double, now: Double = Date().timeIntervalSince1970) -> MotionPath? {
        let age = now - gps.at
        guard age >= -1, age <= gpsMaxAgeS, gps.accuracyM <= gpsMaxAccuracyM else { return nil }
        guard let hit = projectOnShape(shape, lat: gps.lat, lon: gps.lon, near: near), hit.dist <= offRouteM else { return nil }
        let t = nowServer - max(0, age)
        let sinceFix = max(0, t - m.t)
        guard hit.along >= m.a - behindFixM, hit.along <= m.a + aheadMaxSpeed * sinceFix + aheadSlackM else { return nil }
        let end = shape.cum.last ?? hit.along
        let v = gps.speed.map { min(aheadMaxSpeed, max(0, $0)) } ?? 0
        return MotionPath(s: m.s, t: t, k: [[hit.along, 0], [min(end, hit.along + v * extrapolateS), extrapolateS]])
    }
}

/// Shapes, fetched once and cached for the session. A failed fetch retries
/// after 30 s so one error never freezes the vehicles; a 404 is final.
@MainActor
final class ShapeStore {
    static let shared = ShapeStore()

    private var shapes: [String: ShapeLine?] = [:]
    private var loading: Set<String> = []
    private var retryAt: [String: Date] = [:]
    private let retryDelay: TimeInterval = 30

    /// The shape if it is loaded; otherwise starts loading it and returns nil.
    func shape(_ id: String) -> ShapeLine? {
        if let hit = shapes[id] { return hit }
        guard !loading.contains(id), (retryAt[id] ?? .distantPast) <= Date() else { return nil }
        loading.insert(id)
        Task { await load(id) }
        return nil
    }

    private func load(_ id: String) async {
        defer { loading.remove(id) }
        do {
            let url = try APIClient.shared.url(path: "/gtfs/shape", queryItems: [URLQueryItem(name: "id", value: id)])
            let (data, response) = try await APIClient.shared.session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 404 {
                shapes[id] = .some(nil)
                return
            }
            guard (200..<300).contains(status) else { throw APIError.badStatus(status) }
            let shape: ShapeLine = try APIClient.shared.decode(data)
            shapes[id] = .some(shape.pts.count > 1 ? shape : nil)
        } catch {
            retryAt[id] = Date().addingTimeInterval(retryDelay)
        }
    }
}

enum LiveMotionEstimator {
    private static let maxExtrapolateS: Double = 90
    private static let easeMaxM: Double = 400
    private static let easeShare: Double = 0.3
    private static let easeMinStepM: Double = 8

    /// The point `along` metres into the shape.
    static func pointAt(_ shape: ShapeLine, _ along: Double) -> CLLocationCoordinate2D {
        let pts = shape.pts, cum = shape.cum
        let coord = { (p: [Double]) in CLLocationCoordinate2D(latitude: p[0], longitude: p[1]) }
        guard let first = pts.first, let lastPt = pts.last, let lastCum = cum.last else {
            return CLLocationCoordinate2D()
        }
        if along <= 0 { return coord(first) }
        if along >= lastCum { return coord(lastPt) }
        var lo = 0
        var hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) >> 1
            if cum[mid] <= along { lo = mid } else { hi = mid }
        }
        let f = (along - cum[lo]) / max(1e-6, cum[hi] - cum[lo])
        return CLLocationCoordinate2D(
            latitude: pts[lo][0] + (pts[hi][0] - pts[lo][0]) * f,
            longitude: pts[lo][1] + (pts[hi][1] - pts[lo][1]) * f
        )
    }

    /// The vehicle's estimated place now. `shown` is the previous drawing: a
    /// new fix glides instead of jumping, and a lead waits for the bus.
    /// `onboard`: the phone's position when the rider is on this vehicle.
    @MainActor
    static func estimate(
        _ m: LiveMotion?,
        nowServer: Double,
        shown: ShownMotion?,
        onboard: GeoPosition? = nil
    ) -> (coordinate: CLLocationCoordinate2D, shown: ShownMotion)? {
        guard let m, let shape = ShapeStore.shared.shape(m.s) else { return nil }
        let path = m.k.flatMap { $0.isEmpty ? nil : MotionPath(s: m.s, t: m.t, k: $0) }
        if let onboard {
            let near = shown?.shape == m.s ? (shown?.along ?? m.a) : path.map { MotionFollow.pathAt($0, nowServer) } ?? m.a
            if let gps = Onboard.onboardPath(onboard, shape: shape, motion: m, near: near, nowServer: nowServer) {
                let next = MotionFollow.followPath(gps, nowServer, shown)
                return (pointAt(shape, next.along), next)
            }
        }
        if let path {
            let next = MotionFollow.followPath(path, nowServer, shown)
            return (pointAt(shape, next.along), next)
        }
        let dt = max(0, min(maxExtrapolateS, nowServer - m.t))
        var along = min(m.a + m.v * dt, max(m.a, m.e))
        if let shown, shown.shape == m.s {
            let gap = along - shown.along
            if gap < 0, -gap < easeMaxM {
                along = shown.along
            } else if gap > easeMinStepM, gap < easeMaxM {
                along = shown.along + max(easeMinStepM, gap * easeShare)
            }
        }
        return (pointAt(shape, along), ShownMotion(shape: m.s, along: along))
    }
}
