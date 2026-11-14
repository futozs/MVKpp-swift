//
//  TripProgressModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// Polls `/live/trip-progress` for one run.
@MainActor
final class TripProgressModel: ObservableObject {
    @Published private(set) var progress: TripProgressResponse?
    @Published private(set) var errorMessage: String?

    private let pollInterval: TimeInterval = 5
    private var task: Task<Void, Never>?

    func start(tripId: String, vehicleId: String?) async {
        stop()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.load(tripId: tripId, vehicleId: vehicleId)
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func load(tripId: String, vehicleId: String?) async {
        do {
            progress = try await APIClient.shared.tripProgress(tripId: tripId, vehicleId: vehicleId)
            errorMessage = nil
        } catch {
            // Like the web rail: a failed poll replaces the rail with the
            // reason until the next one succeeds.
            errorMessage = error.localizedDescription
        }
    }

    deinit { task?.cancel() }
}
