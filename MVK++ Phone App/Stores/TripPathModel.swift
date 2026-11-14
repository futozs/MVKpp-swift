//
//  TripPathModel.swift
//  MVK++ Phone App
//

import Combine
import CoreLocation
import Foundation

/// Polls one trip's path and vehicle position while the rider is following it.
///
/// `isLost` means the gateway still knows the trip but the vehicle has stopped
/// reporting — worth saying out loud, because the map will otherwise look
/// simply frozen.
@MainActor
final class TripPathModel: ObservableObject {

    @Published private(set) var path: TripPathResponse?
    @Published private(set) var isLost = false

    private let pollInterval: TimeInterval = 4
    private var task: Task<Void, Never>?
    private var currentKey: String?

    var shape: [CLLocationCoordinate2D] {
        (path?.shape ?? []).compactMap { point in
            guard point.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
        }
    }

    var vehicleFix: ApproachEngine.VehicleFix? {
        guard let vehicle = path?.vehicle else { return nil }
        return ApproachEngine.VehicleFix(lat: vehicle.lat, lon: vehicle.lon, speed: vehicle.speed)
    }

    /// `active` false pauses the polling but keeps the last path, so coming
    /// back to the map does not flash an empty dock.
    func follow(tripId: String?, vehicleId: String?, active: Bool = true) {
        let key = "\(tripId ?? "")|\(vehicleId ?? "")"
        let shouldPoll = active && tripId != nil
        if key != currentKey {
            currentKey = key
            path = nil
            isLost = false
        } else if (task != nil) == shouldPoll {
            return
        }

        task?.cancel()
        task = nil

        guard shouldPoll, let tripId else { return }

        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.load(tripId: tripId, vehicleId: vehicleId)
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    private func load(tripId: String, vehicleId: String?) async {
        do {
            let response = try await APIClient.shared.tripPath(tripId: tripId, vehicleId: vehicleId)
            guard !Task.isCancelled else { return }
            path = response
            isLost = response.vehicle == nil
        } catch {
            guard !Task.isCancelled else { return }
            isLost = true
        }
    }

    deinit { task?.cancel() }
}
