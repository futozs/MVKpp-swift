//
//  BoardingDetector.swift
//  MVK++ Phone App
//
//  Port of `ride/useBoardingDetector.ts`: when the phone moves together with
//  a vehicle over several samples, ask whether the rider is on it. On the
//  phone, Core Motion's activity classifier sharpens it: a confident
//  „automotive” reading lets the question come a sample sooner, and a
//  confident „walking” reading never counts as riding along.
//

import CoreMotion
import Foundation

/// A vehicle the phone has been moving with, and where it stood beside it
/// before they set off.
struct BoardingCandidate: Equatable {
    let vehicle: LiveVehicle
    let since: BoardingSpot
}

@MainActor
final class BoardingDetector {
    /// At least this long between two samples (s); GPS can report every second.
    private static let sampleS: Double = 10
    private static let hits = 3
    private static let minSpanS: Double = 40
    /// With Core Motion confidently saying „in a vehicle”.
    private static let automotiveHits = 2
    private static let automotiveMinSpanS: Double = 25
    /// The phone moved at least this much between samples (m): never ask about a standing bus.
    private static let movedM: Double = 30
    /// After „Nem”, the same vehicle is not asked about for this long (s).
    private static let snoozeS: Double = 30 * 60

    private struct Hit {
        var n: Int
        var first: Double
        var spot: BoardingSpot
    }

    private var last: BoardingSpot?
    private var hits: [String: Hit] = [:]
    private var snoozed: [String: Double] = [:]

    private let activity = CMMotionActivityManager()
    private var automotive = false
    private var walking = false
    private var activityRunning = false

    func startMotion() {
        guard !activityRunning, CMMotionActivityManager.isActivityAvailable() else { return }
        let status = CMMotionActivityManager.authorizationStatus()
        guard status != .denied, status != .restricted else { return }
        activityRunning = true
        activity.startActivityUpdates(to: .main) { [weak self] a in
            guard let a else { return }
            MainActor.assumeIsolated {
                let sure = a.confidence != .low
                self?.automotive = a.automotive && sure
                self?.walking = (a.walking || a.running) && !a.automotive && a.confidence == .high
            }
        }
    }

    func stopMotion() {
        guard activityRunning else { return }
        activity.stopActivityUpdates()
        activityRunning = false
        automotive = false
        walking = false
    }

    func reset() {
        last = nil
        hits = [:]
    }

    /// „Nem”: this vehicle is not asked about again for a while.
    func snooze(_ vehicleId: String) {
        snoozed[vehicleId] = Date().timeIntervalSince1970 + Self.snoozeS
    }

    /// Feeds one position; returns a candidate when it is time to ask.
    func sample(_ position: GeoPosition, vehicles: [LiveVehicle]) -> BoardingCandidate? {
        let prev = last
        if let prev, position.at - prev.at < Self.sampleS { return nil }
        let here = BoardingSpot(at: position.at, lat: position.lat, lon: position.lon)
        last = here
        let moved = prev.map { RideLogic.distM(RidePoint(lat: $0.lat, lon: $0.lon), RidePoint(lat: position.lat, lon: position.lon)) >= Self.movedM } ?? false
        let now = Date().timeIntervalSince1970
        let needHits = automotive ? Self.automotiveHits : Self.hits
        let needSpan = automotive ? Self.automotiveMinSpanS : Self.minSpanS
        let nowServer = RealtimeClient.shared.serverNow
        let me = RidePoint(lat: position.lat, lon: position.lon)

        for v in vehicles {
            guard let lat = v.lat, let lon = v.lon, !v.tripId.isEmpty else { continue }
            if (snoozed[v.id] ?? 0) > now { continue }
            // Never ask beside a vehicle whose position is a timetable estimate.
            if v.estimated == true { continue }
            let px = v.rideMode.proximity
            let near = max(px.near, min(px.near + 70, position.accuracyM))
            // The bus's signal is 0–15 s old (150+ m behind on a fast stretch): compare with its estimate now.
            let est = LiveMotionEstimator.estimate(v.motion, nowServer: nowServer, shown: nil)?.coordinate
            let d = RideLogic.distM(me, RidePoint(lat: est?.latitude ?? lat, lon: est?.longitude ?? lon))
            let h = hits[v.id]
            if d > px.far {
                hits[v.id] = nil
                continue
            }
            if d > near { continue }
            if !moved || walking {
                // Standing together (boarding at the stop): until they set off, this is the boarding spot.
                if let h, h.n > 0 { hits[v.id] = h } else { hits[v.id] = Hit(n: 0, first: 0, spot: here) }
                continue
            }
            let next: Hit
            if let h, h.n > 0 {
                next = Hit(n: h.n + 1, first: h.first, spot: h.spot)
            } else {
                next = Hit(n: 1, first: position.at, spot: h?.spot ?? here)
            }
            hits[v.id] = next
            if next.n >= needHits, position.at - next.first >= needSpan {
                hits = [:]
                return BoardingCandidate(vehicle: v, since: next.spot)
            }
        }
        return nil
    }
}

/// During a ride: the phone far from the bus for long means the rider got
/// off — `true` once it has been more than `away` metres for two minutes.
struct AlightingDetector {
    private var since: Double?

    mutating func sample(enabled: Bool, position: GeoPosition?, vehicle: RidePoint?, awayM: Double = 300) -> Bool {
        guard enabled, let position, let vehicle else {
            since = nil
            return false
        }
        if RideLogic.distM(RidePoint(lat: position.lat, lon: position.lon), vehicle) <= awayM {
            since = nil
            return false
        }
        let start = since ?? position.at
        since = start
        if position.at - start >= 120 {
            since = nil
            return true
        }
        return false
    }
}
