//
//  LineFavoritesStore.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Combine
import Foundation

/// A saved route + direction pair, so a commuter's own line is one tap away
/// instead of a scroll through fifty routes.
struct FavoriteLine: Codable, Hashable, Identifiable {
    let routeId: String
    let dir: String

    var id: String { "\(routeId)|\(dir)" }
}

@MainActor
final class LineFavoritesStore: ObservableObject {

    static let maxCount = 24
    private static let storageKey = "mvk_timetable_favorites"

    @Published private(set) var lines: [FavoriteLine] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([FavoriteLine].self, from: data) {
            lines = Array(decoded.prefix(Self.maxCount))
        }
    }

    func contains(routeId: String, dir: String) -> Bool {
        lines.contains { $0.routeId == routeId && $0.dir == dir }
    }

    func toggle(routeId: String, dir: String) {
        if let index = lines.firstIndex(where: { $0.routeId == routeId && $0.dir == dir }) {
            lines.remove(at: index)
        } else {
            guard lines.count < Self.maxCount else { return }
            lines.append(FavoriteLine(routeId: routeId, dir: dir))
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(lines) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
