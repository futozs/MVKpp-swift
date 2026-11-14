//
//  ParkingModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// The parking state (web `useParking`): first load over HTTP, then the
/// server pushes it on the `parking` topic; polling only as a fallback while
/// the socket is down.
@MainActor
final class ParkingModel: ObservableObject {
    @Published private(set) var data: ParkingSnapshot?
    @Published private(set) var error: String?
    /// Bumps every 15 s so the "X perce" labels keep moving between pushes.
    @Published private(set) var tick = 0

    private var received: (at: Double, local: Double)?
    private var subscription: AnyCancellable?
    private var loops: [Task<Void, Never>] = []

    private let pollInterval: Duration = .seconds(15)
    private let tickInterval: Duration = .seconds(15)
    private let connectGrace: Duration = .milliseconds(2500)

    /// The server clock now (unix s), from the snapshot's `at` and the time
    /// since it arrived — right even when the phone's clock is off.
    var now: Double {
        let local = Date().timeIntervalSince1970
        guard let received else { return local.rounded() }
        return (received.at + (local - received.local)).rounded()
    }

    func start() {
        guard subscription == nil else { return }
        Task { await load() }
        subscription = RealtimeClient.shared.subscribe("parking") { [weak self] message in
            guard let snapshot = try? message.decode(ParkingPush.self).data else { return }
            self?.apply(snapshot)
        }
        loops.append(Task { [weak self] in
            try? await Task.sleep(for: self?.connectGrace ?? .zero)
            while !Task.isCancelled {
                guard let self else { return }
                if !RealtimeClient.shared.connected { await self.load() }
                try? await Task.sleep(for: self.pollInterval)
            }
        })
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.tickInterval ?? .seconds(15))
                self?.tick += 1
            }
        })
    }

    func stop() {
        subscription = nil
        loops.forEach { $0.cancel() }
        loops = []
    }

    private struct ParkingPush: Decodable {
        let data: ParkingSnapshot?
    }

    private func load() async {
        do {
            apply(try await APIClient.shared.parking())
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply(_ snapshot: ParkingSnapshot) {
        received = (snapshot.at, Date().timeIntervalSince1970)
        data = snapshot
        error = nil
    }
}

/// The forda-tábla (`/engine/blocks`), refreshed every minute.
@MainActor
final class ParkingBlocksModel: ObservableObject {
    @Published private(set) var data: ParkingBlocks?
    @Published private(set) var error: String?
    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    self.data = try await APIClient.shared.parkingBlocks()
                    self.error = nil
                } catch {
                    self.error = error.localizedDescription
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}
