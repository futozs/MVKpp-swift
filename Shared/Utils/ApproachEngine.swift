//
//  ApproachEngine.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Combine
import CoreLocation
import Foundation

enum ApproachState {
    /// No fix, so nothing can be said about the rider's position.
    case noGPS
    /// The run has no vehicle assigned yet.
    case noVehicle
    /// The rider is not standing anywhere near this route's path.
    case offRoute
    /// The vehicle is behind the rider and closing.
    case inbound
    /// The vehicle has already gone past.
    case passed
}

struct Approach {
    let state: ApproachState
    /// Along-route distance for `inbound`/`passed`, straight-line for `offRoute`.
    let distanceKm: Double?
    /// True when `distanceKm` is a crow-flies figure rather than route distance.
    let straightLine: Bool
    let etaMin: Int?
    let speedKmh: Double?

    static let noGPS = Approach(state: .noGPS, distanceKm: nil, straightLine: false, etaMin: nil, speedKmh: nil)
    static let noVehicle = Approach(state: .noVehicle, distanceKm: nil, straightLine: false, etaMin: nil, speedKmh: nil)
}

/// Answers "how long until *this* bus reaches *me*", which the arrivals feed
/// cannot: it gives a scheduled ETA for the stop, not for wherever the rider
/// is actually standing.
///
/// Both the rider and the vehicle are projected onto the trip's shape, and the
/// gap between those projections is the real remaining distance. Speed comes
/// from how far the vehicle has moved along that shape over the last few
/// minutes — far steadier than the instantaneous GPS speed, which reads zero
/// at every red light.
@MainActor
final class ApproachEngine: ObservableObject {

    @Published private(set) var approach: Approach = .noGPS

    /// Beyond this the rider is not on the route at all.
    private static let maxOffRouteKm = 1.2
    /// Inside this the vehicle counts as "here", not "passed".
    private static let hereKm = 0.05
    private static let speedWindow: TimeInterval = 180
    /// Below this the sample window is too short to trust.
    private static let minSpeedSample: TimeInterval = 40
    /// Used before enough samples accumulate — roughly urban bus average.
    private static let fallbackKmh = 17.0
    private static let minKmh = 6.0
    private static let maxKmh = 70.0

    private struct Sample {
        let alongKm: Double
        let at: TimeInterval
    }

    private var samples: [Sample] = []
    private var currentTripId: String?
    private var avgKmh: Double?

    struct VehicleFix {
        let lat: Double
        let lon: Double
        /// Metres per second.
        let speed: Double?
    }

    func update(
        tripId: String?,
        shape: [CLLocationCoordinate2D]?,
        vehicle: VehicleFix?,
        position: GeoPosition?
    ) {
        if currentTripId != tripId {
            currentTripId = tripId
            samples = []
            avgKmh = nil
        }

        let usableShape = (shape?.count ?? 0) >= 2 ? shape : nil
        let busProjection = usableShape.flatMap { path in
            vehicle.flatMap { Geo.projectOntoPath(path, lat: $0.lat, lon: $0.lon) }
        }

        if let busAlongKm = busProjection?.alongKm {
            recordSample(alongKm: busAlongKm)
        }

        guard let position else {
            approach = .noGPS
            return
        }
        guard let vehicle else {
            approach = .noVehicle
            return
        }

        let crowKm = Geo.distanceKm(position.lat, position.lon, vehicle.lat, vehicle.lon)
        let myProjection = usableShape.flatMap {
            Geo.projectOntoPath($0, lat: position.lat, lon: position.lon)
        }

        guard let myProjection, let busProjection, myProjection.distKm <= Self.maxOffRouteKm else {
            approach = Approach(
                state: .offRoute,
                distanceKm: crowKm,
                straightLine: true,
                etaMin: nil,
                speedKmh: nil
            )
            return
        }

        let remainingKm = myProjection.alongKm - busProjection.alongKm

        if remainingKm < -Self.hereKm {
            approach = Approach(
                state: .passed,
                distanceKm: abs(remainingKm),
                straightLine: false,
                etaMin: nil,
                speedKmh: nil
            )
            return
        }

        // Prefer the windowed average; fall back to the instantaneous reading
        // only when the vehicle is clearly rolling, otherwise a typical speed.
        let instantKmh = vehicle.speed.map { $0 * 3.6 }
        let rawKmh = avgKmh
            ?? ((instantKmh ?? 0) > 8 ? instantKmh! : Self.fallbackKmh)
        let speedKmh = min(Self.maxKmh, max(Self.minKmh, rawKmh))
        let distance = max(0, remainingKm)

        approach = Approach(
            state: .inbound,
            distanceKm: distance,
            straightLine: false,
            etaMin: Int(((distance / speedKmh) * 60).rounded()),
            speedKmh: speedKmh
        )
    }

    func reset() {
        samples = []
        avgKmh = nil
        currentTripId = nil
        approach = .noGPS
    }

    /// Keeps a rolling window of positions along the route. A sample is only
    /// added once the vehicle has actually moved (4 m) or 20 s have passed, so
    /// a bus idling at a terminus does not flood the window with duplicates.
    private func recordSample(alongKm: Double) {
        let now = Date().timeIntervalSince1970

        if let last = samples.last {
            let moved = abs(last.alongKm - alongKm) > 0.004
            let waited = now - last.at > 20
            if moved || waited {
                samples.append(Sample(alongKm: alongKm, at: now))
            }
        } else {
            samples.append(Sample(alongKm: alongKm, at: now))
        }

        while samples.count > 2, now - samples[0].at > Self.speedWindow {
            samples.removeFirst()
        }

        guard let first = samples.first else { return }
        let elapsed = now - first.at
        let movedKm = alongKm - first.alongKm
        avgKmh = (elapsed >= Self.minSpeedSample && movedKm > 0)
            ? (movedKm / elapsed) * 3600
            : nil
    }
}
