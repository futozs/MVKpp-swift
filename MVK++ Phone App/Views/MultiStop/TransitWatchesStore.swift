//
//  TransitWatchesStore.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// A to B directly (e.g. Miskolc-Tiszai → Füzesabony).
struct RelationWatch: Codable, Hashable, Identifiable {
    let from: String
    let to: String

    var id: String { "\(from)>\(to)" }
}

/// The Figyelő's other cards beside the stops — the web app's
/// `lib/transitWatches`: relations (A → B) and train numbers (every day).
/// Their own `mvk_watch_*` keys, so cloud sync carries them separately and
/// older clients' stop lists stay untouched.
@MainActor
final class TransitWatchesStore: ObservableObject {
    static let shared = TransitWatchesStore()

    static let relationsKey = "mvk_watch_relations"
    static let trainsKey = "mvk_watch_trains"
    /// Each card polls, so the lists are capped.
    static let maxRelations = 6
    static let maxTrains = 6

    @Published private(set) var relations: [RelationWatch] = []
    @Published private(set) var trains: [String] = []

    private var observer: AnyCancellable?

    private init() {
        reload()
        observer = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    func addRelation(_ relation: RelationWatch) {
        guard !relations.contains(relation) else { return }
        setRelations(relations + [relation])
    }

    func removeRelation(_ relation: RelationWatch) {
        setRelations(relations.filter { $0 != relation })
    }

    func toggleTrain(_ number: String) {
        if trains.contains(number) {
            setTrains(trains.filter { $0 != number })
        } else {
            setTrains(trains + [number])
        }
    }

    private func setRelations(_ next: [RelationWatch]) {
        relations = Array(next.prefix(Self.maxRelations))
        write(relations, key: Self.relationsKey)
    }

    private func setTrains(_ next: [String]) {
        var seen = Set<String>()
        trains = Array(next.filter { seen.insert($0).inserted }.prefix(Self.maxTrains))
        write(trains, key: Self.trainsKey)
    }

    private func reload() {
        let nextRelations = (Self.read([RelationWatch].self, key: Self.relationsKey) ?? []).prefix(Self.maxRelations)
        let nextTrains = (Self.read([String].self, key: Self.trainsKey) ?? []).filter(Self.isTrainNumber).prefix(Self.maxTrains)
        if Array(nextRelations) != relations { relations = Array(nextRelations) }
        if Array(nextTrains) != trains { trains = Array(nextTrains) }
    }

    static func isTrainNumber(_ value: String) -> Bool {
        (1...6).contains(value.count) && value.allSatisfy(\.isNumber)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: key) ?? defaults.string(forKey: key).map({ Data($0.utf8) }) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
