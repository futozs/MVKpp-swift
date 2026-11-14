//
//  StopEntity.swift
//  MVK++ (shared by the Phone, Watch and Widget targets)
//

import AppIntents
import Foundation

/// A stop, as the widget editor sees it.
///
/// Configuration lives on the widget rather than in app settings so a rider
/// can put two of these on the home screen — home stop and work stop — and
/// have each show its own countdown.
struct StopEntity: AppEntity, Identifiable, Hashable {
    let id: String
    let name: String
    let code: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Megálló"
    static let defaultQuery = StopEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(code). megálló"
        )
    }

    init(id: String, name: String, code: String) {
        self.id = id
        self.name = name
        self.code = code
    }

    init(_ stop: CachedStop) {
        id = stop.id
        name = stop.name
        code = stop.riderCode
    }
}

/// Answers the picker in the widget editor.
///
/// Everything comes out of the App Group copy of the stop catalog: an entity
/// query is given a fraction of a second, which is not enough for a cold HTTP
/// request. The network path exists only for the case where the app has never
/// finished a launch.
struct StopEntityQuery: EntityStringQuery {

    func entities(for identifiers: [StopEntity.ID]) async throws -> [StopEntity] {
        let wanted = Set(identifiers)
        let cached = await catalog().filter { wanted.contains($0.id) }
        return cached.map(StopEntity.init)
    }

    func entities(matching string: String) async throws -> [StopEntity] {
        let stops = await catalog()
        let needle = string
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        guard !needle.isEmpty else { return Array(ranked(stops).prefix(40)) }

        return stops
            .filter {
                $0.name.folding(options: .diacriticInsensitive, locale: .current)
                    .lowercased().contains(needle)
                    || $0.riderCode.hasPrefix(needle)
            }
            .prefix(40)
            .map(StopEntity.init)
    }

    /// The watchlist comes first: those are the stops the rider already told
    /// the app they care about, and one of them is almost always the answer.
    func suggestedEntities() async throws -> [StopEntity] {
        Array(ranked(await catalog()).prefix(40))
    }

    func defaultResult() async -> StopEntity? {
        try? await suggestedEntities().first
    }

    private func ranked(_ stops: [CachedStop]) -> [StopEntity] {
        let watched = FavoritesStore.storedStopIds
        let index = Dictionary(stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let favourites = watched.compactMap { index[$0] }
        let watchedSet = Set(watched)
        return (favourites + stops.filter { !watchedSet.contains($0.id) }).map(StopEntity.init)
    }

    private func catalog() async -> [CachedStop] {
        let cached = SharedStopCache.load()
        guard cached.isEmpty else { return cached }
        guard let fetched = try? await APIClient.shared.stops() else { return [] }
        SharedStopCache.save(fetched)
        return fetched.map(CachedStop.init)
    }
}
