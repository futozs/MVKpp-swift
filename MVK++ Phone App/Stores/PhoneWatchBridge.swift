//
//  PhoneWatchBridge.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// Keeps the watch on the phone's settings: transport modes, stop merge,
/// timetable favourites and the predicted-vehicle switch. The watchlist rides
/// on `FavoritesStore`; the ride store publishes its own snapshots through
/// `WatchLink.shared.publish(ride:)`.
@MainActor
final class PhoneWatchBridge {
    static let shared = PhoneWatchBridge()

    private var cancellable: AnyCancellable?
    private var lastSent: WatchSettings?

    func start() {
        guard cancellable == nil else { return }
        WatchLink.shared.activate()
        publishSettings()
        // Settings change through `LocalStore`, a cloud sync, or a store
        // writing `UserDefaults` itself — every one of them ends up here.
        cancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { _ in
                Task { @MainActor in PhoneWatchBridge.shared.publishSettings() }
            }
    }

    private func publishSettings() {
        let store = LocalStore.shared
        let lines = UserDefaults.standard.data(forKey: "mvk_timetable_favorites")
            .flatMap { try? JSONDecoder().decode([FavoriteLine].self, from: $0) } ?? []
        let settings = WatchSettings(
            modes: store.enabledModes,
            merge: store.stopMerge,
            lineFavorites: lines,
            predictedVehicle: store.bool(Preferences.predictedVehicleKey)
        )
        guard settings != lastSent else { return }
        lastSent = settings
        WatchLink.shared.publish(settings: settings)
    }
}
