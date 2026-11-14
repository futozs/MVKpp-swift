//
//  FallbackPoll.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// REST polling while the realtime socket is down (web `useFallbackPoll`):
/// after a short grace for the first connect, a drop loads at once and then
/// every `interval`; a reconnect stops it.
@MainActor
final class FallbackPoll {
    private static let connectGrace: Duration = .milliseconds(2500)

    private let interval: Duration
    private let load: @MainActor () async -> Void
    private var graceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var watch: AnyCancellable?
    private var graceOver = false

    init(every interval: Duration, load: @escaping @MainActor () async -> Void) {
        self.interval = interval
        self.load = load
    }

    func start() {
        guard watch == nil else { return }
        graceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.connectGrace)
            guard !Task.isCancelled, let self else { return }
            self.graceOver = true
            self.update(connected: RealtimeClient.shared.connected)
        }
        // `@Published` emits before the property changes, so the new value
        // comes from the publisher, not from `connected`.
        watch = RealtimeClient.shared.$connected
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] connected in self?.update(connected: connected) }
    }

    func stop() {
        graceTask?.cancel()
        pollTask?.cancel()
        graceTask = nil
        pollTask = nil
        watch = nil
        graceOver = false
    }

    private func update(connected: Bool) {
        pollTask?.cancel()
        pollTask = nil
        guard graceOver, !connected else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.load()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    deinit {
        graceTask?.cancel()
        pollTask?.cancel()
    }
}
