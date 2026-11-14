//
//  FavoriteVehiclesStore.swift
//  MVK++ (shared)
//

import Combine
import Foundation

/// Starred vehicles (fleet numbers), the web app's `useFavoriteVehicles`,
/// under the same `mvk_stats_favorite_vehicles` key so cloud sync carries it.
@MainActor
final class FavoriteVehiclesStore: ObservableObject {
    static let shared = FavoriteVehiclesStore()

    static let maxCount = 40
    static let storageKey = "mvk_stats_favorite_vehicles"

    @Published private(set) var vehicleIds: [String] = []
    private var observer: AnyCancellable?

    private init() {
        reload()
        observer = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    func contains(_ vehicleId: String) -> Bool { vehicleIds.contains(vehicleId) }

    func toggle(_ vehicleId: String) {
        if let index = vehicleIds.firstIndex(of: vehicleId) {
            vehicleIds.remove(at: index)
        } else {
            guard vehicleIds.count < Self.maxCount else { return }
            vehicleIds.append(vehicleId)
        }
        guard let data = try? JSONEncoder().encode(vehicleIds) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func reload() {
        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: Self.storageKey) ?? defaults.string(forKey: Self.storageKey).map { Data($0.utf8) }
        let next = data.flatMap { try? JSONDecoder().decode([String].self, from: $0) }.map { Array($0.prefix(Self.maxCount)) } ?? []
        if next != vehicleIds { vehicleIds = next }
    }
}
