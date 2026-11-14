//
//  KioskBoardModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// One stop's departures (web `useStopBoard`): the server pushes them on
/// `stop:<id>@<board key>`; without a socket they are polled.
@MainActor
final class KioskBoardModel: ObservableObject {
    @Published private(set) var data: KioskBoard?
    @Published private(set) var error: String?

    private let stopId: String
    private let boardKey: String
    private var subscription: AnyCancellable?
    private lazy var fallback = FallbackPoll(every: .seconds(10)) { [weak self] in await self?.load() }

    private static let limit = 10

    init(stopId: String, boardKey: String) {
        self.stopId = stopId
        self.boardKey = boardKey
    }

    private struct Push: Decodable {
        let data: KioskBoard?
    }

    func start() {
        guard subscription == nil else { return }
        Task { await load() }
        subscription = RealtimeClient.shared.subscribe("stop:\(stopId)@\(boardKey)") { [weak self] message in
            guard let board = try? message.decode(Push.self).data else { return }
            self?.data = board
            self?.error = nil
        }
        fallback.start()
    }

    func stop() {
        subscription = nil
        fallback.stop()
    }

    private func load() async {
        do {
            data = try await APIClient.shared.kioskBoard(stopId: stopId, limit: Self.limit, boardKey: boardKey)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Stop helpers of the kiosk (web `lib/modes.ts`, `RegionalBits`).
enum KioskStops {
    static let maxCount = 3
    static let storageKey = "mvk_kiosk_stops"

    /// The county, plus the Füzesabony rail junction (`core/transit/region.ts`).
    private static let region: [(Double, Double)] = [
        (48.3, 20.08), (48.3, 20.36), (48.47, 20.48), (48.56, 20.75), (48.55, 21.1), (48.52, 21.25), (48.57, 21.45),
        (48.41, 21.7), (48.38, 22.12), (48.25, 21.93), (48.18, 21.7), (48.1, 21.42), (48.0, 21.1), (47.88, 21.09),
        (47.64, 20.88), (47.7, 20.6), (47.7, 20.35), (47.95, 20.47), (48.08, 20.45), (48.12, 20.2), (48.2, 20.06),
    ]

    static func inRegion(lat: Double, lon: Double) -> Bool {
        var inside = false
        var j = region.count - 1
        for i in region.indices {
            let (yi, xi) = region[i]
            let (yj, xj) = region[j]
            if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Search order: stops inside the county first.
    static func regionRank(_ s: Stop) -> Int {
        !TransitModes.isRegionalId(s.id) || inRegion(lat: s.lat, lon: s.lon) ? 0 : 1
    }

    /// A station's platforms and bays are not separate items: the station shows them all.
    static func pickable(_ stops: [Stop]) -> [Stop] {
        let ids = Set(stops.map(\.id))
        return stops.filter { s in
            guard let parent = s.parent else { return true }
            return !ids.contains(parent)
        }
    }

    /// A regional stop's kind in the header; MVK keeps its stop ID.
    static func kindLabel(_ stop: Stop) -> String {
        let feed = stop.feed ?? TransitModes.feed(ofId: stop.id).rawValue
        if feed == "rail" { return "Vasútállomás" }
        if feed == "coach" { return stop.station ? "Autóbusz-állomás" : "Volán-megálló" }
        return stop.id
    }

    static func kindLabel(id: String) -> String {
        switch TransitModes.feed(ofId: id) {
        case .rail: return "Vasútállomás"
        case .coach: return "Volán-megálló"
        case .mvk: return id
        }
    }
}
