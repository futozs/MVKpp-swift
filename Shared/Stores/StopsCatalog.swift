//
//  StopsCatalog.swift
//  MVK++ Watch App
//

import Combine
import Foundation

/// The full stop list, fetched once per app session and held in memory for
/// on-device search (a few hundred stops — cheap to keep resident).
///
/// Mirrored into the App Group on every successful fetch, and read back from
/// there when the network is gone. Typing a stop code is something riders do
/// standing at a stop, which is exactly where the signal is worst.
@MainActor
final class StopsCatalog: ObservableObject {
    @Published private(set) var stops: [Stop] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// The list came off the device rather than the gateway.
    @Published private(set) var isOffline = false

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await APIClient.shared.stops()
            stops = loaded
            hasLoaded = true
            isOffline = false
            errorMessage = nil
            SharedStopCache.save(loaded)
        } catch {
            let mirrored = SharedStopCache.loadStops()
            guard !mirrored.isEmpty else {
                errorMessage = error.localizedDescription
                return
            }
            // Deliberately not `hasLoaded`: the next chance at the network
            // should still be taken.
            stops = mirrored
            isOffline = true
            errorMessage = nil
        }
    }
}
