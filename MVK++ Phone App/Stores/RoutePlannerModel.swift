//
//  RoutePlannerModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// The rider's regional picks for planning: MVK is always in, Volán and rail
/// can be ticked. Until touched they follow the transport-mode settings.
struct PlanTravel: Equatable {
    var coach: Bool
    var rail: Bool

    /// With no result: what is still worth ticking.
    var emptyHint: String? {
        if coach && rail { return nil }
        if !coach && !rail {
            return "Lehet, hogy csak MVK-val nem érhető el. Pipáld be a Volánt vagy a vonatot, vagy próbálj másik időpontot."
        }
        return rail
            ? "Lehet, hogy Volán nélkül nem érhető el. Pipáld be a Volánt, vagy próbálj másik időpontot."
            : "Lehet, hogy vonat nélkül nem érhető el. Pipáld be a vonatot, vagy próbálj másik időpontot."
    }
}

struct PlanFormValue: Equatable {
    var from = ""
    var to = ""
    var arriveBy = false
    /// YYYY-MM-DD, Budapest.
    var date: String
    /// HH:MM, Budapest.
    var time: String
}

/// The route planner on top of our own `/engine/plan`: one request brings the
/// timetable itinerary and, beside it, the measured departure and arrival for
/// a past day, or the expected lateness (live or from earlier measurements)
/// and the transfer risk for today and later.
@MainActor
final class RoutePlannerModel: ObservableObject {

    enum Result {
        case idle
        case loading
        case error(String)
        case done(JourneyPlanResponse)
    }

    /// The backend's rule: more than 10 minutes ahead is "future".
    static let nowWindowSec = 600.0
    static let resultLimit = 4
    /// A live plan is refreshed quietly this often.
    static let liveRefresh: Duration = .seconds(60)

    private static let coachKey = "mvk_pref_plan_coach"
    private static let railKey = "mvk_pref_plan_rail"

    @Published var form: PlanFormValue
    @Published private(set) var result: Result = .idle
    @Published private(set) var places: [PlannerPlace] = []
    @Published private(set) var travel: PlanTravel

    private var lastQuery: JourneyPlanQuery?
    private var runTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var placesTask: Task<Void, Never>?
    private var ownStops: (key: String, places: [PlannerPlace])?
    private var catalog: [Stop] = []
    private var lastModes: String?

    init() {
        form = PlanFormValue(date: PlannerFormat.todayLocalIso(), time: PlannerFormat.nowLocalTime())
        travel = PlanTravel(coach: false, rail: false)
        travel = resolvedTravel()
        lastModes = modes
    }

    var isLoading: Bool {
        if case .loading = result { return true }
        return false
    }

    var mode: JourneyMode {
        if form.date < PlannerFormat.todayLocalIso() { return .past }
        let at = Double(PlannerFormat.toUnix(date: form.date, time: form.time))
        return at > RealtimeClient.shared.serverNow + Self.nowWindowSec ? .future : .now
    }

    var canSubmit: Bool {
        !form.from.isEmpty && !form.to.isEmpty && form.from != form.to
    }

    /// The `?modes=` of this plan: tram and bus always, plus the ticked regional modes.
    var modes: String {
        var list: [TransitMode] = [.tram, .bus]
        if travel.coach { list.append(.coach) }
        if travel.rail { list.append(.rail) }
        return TransitMode.param(list)
    }

    // MARK: - Travel modes

    private func resolvedTravel() -> PlanTravel {
        let enabled = TransitMode.enabled()
        let local = LocalStore.shared
        return PlanTravel(
            coach: local.json(Self.coachKey, as: Bool.self) ?? enabled.contains(.coach),
            rail: local.json(Self.railKey, as: Bool.self) ?? enabled.contains(.rail)
        )
    }

    func setTravel(coach: Bool? = nil, rail: Bool? = nil) {
        if let coach { LocalStore.shared.setBool(Self.coachKey, coach) }
        if let rail { LocalStore.shared.setBool(Self.railKey, rail) }
        travel = resolvedTravel()
        travelChanged()
    }

    // MARK: - Places

    /// Called with the app's stop catalog; regional stops are fetched with
    /// their feed and parent station so the list follows the ticks.
    func updateCatalog(_ stops: [Stop]) {
        catalog = stops
        rebuildPlaces()
        loadOwnStops()
    }

    private func loadOwnStops() {
        let key = modes
        guard ownStops?.key != key else { return }
        placesTask?.cancel()
        placesTask = Task { [weak self] in
            guard let list = try? await APIClient.shared.plannerPlaces(modes: key), !Task.isCancelled else { return }
            guard let self, self.modes == key else { return }
            self.ownStops = (key, list)
            self.rebuildPlaces()
            self.dropGonePlaces()
        }
    }

    private func rebuildPlaces() {
        let source = ownStops?.key == modes ? ownStops?.places ?? [] : catalog.map(PlannerPlace.init(stop:))
        let merge = LocalStore.shared.stopMerge
        let ids = Set(source.map(\.id))
        var byName: [String: PlannerPlace] = [:]
        var order: [String] = []
        for place in source {
            if let parent = place.parent, ids.contains(parent) { continue }
            let feed = place.resolvedFeed
            let allowed = feed == .mvk || (feed == .coach ? travel.coach : travel.rail)
            guard allowed else { continue }
            if place.twinOf != nil && merge != .off { continue }
            guard byName[place.name] == nil else { continue }
            byName[place.name] = place
            order.append(place.name)
        }
        let hungarian = Locale(identifier: "hu_HU")
        places = order.compactMap { byName[$0] }.sorted { a, b in
            let ra = Self.regionRank(a), rb = Self.regionRank(b)
            if ra != rb { return ra < rb }
            return a.name.compare(b.name, locale: hungarian) == .orderedAscending
        }
    }

    /// Stops inside the county first; regional lines run their whole route,
    /// so Debrecen's bus station is on the list too — but at the back.
    private static func regionRank(_ place: PlannerPlace) -> Int {
        !TransitIds.isRegional(place.id) || PlannerRegion.contains(lat: place.lat, lon: place.lon) ? 0 : 1
    }

    func placeName(_ id: String) -> PlannerPlace? {
        places.first { $0.id == id }
    }

    // MARK: - Form

    func setNow() {
        form.date = PlannerFormat.todayLocalIso()
        form.time = PlannerFormat.nowLocalTime()
    }

    func swap() {
        let from = form.from
        form.from = form.to
        form.to = from
    }

    /// On re-ticking: a place no longer offered (e.g. Budapest-Keleti without
    /// rail) is cleared; otherwise an existing plan is recomputed with the new modes.
    private func travelChanged() {
        guard modes != lastModes else { return }
        lastModes = modes
        rebuildPlaces()
        loadOwnStops()
        if dropGonePlaces() { return }
        if lastQuery != nil { run() }
    }

    @discardableResult
    private func dropGonePlaces() -> Bool {
        let ids = Set(places.map(\.id))
        var gone = false
        if !form.from.isEmpty && !ids.contains(form.from) { form.from = ""; gone = true }
        if !form.to.isEmpty && !ids.contains(form.to) { form.to = ""; gone = true }
        guard gone else { return false }
        runTask?.cancel()
        lastQuery = nil
        result = .idle
        stopRefresh()
        return true
    }

    // MARK: - Search

    func submit() {
        guard canSubmit, !isLoading else { return }
        run()
    }

    func run(silent: Bool = false) {
        let query: JourneyPlanQuery?
        if silent {
            if var last = lastQuery, !last.arriveBy {
                last.at = Int(RealtimeClient.shared.serverNow)
                query = last
            } else {
                query = lastQuery
            }
        } else if canSubmit {
            query = JourneyPlanQuery(
                from: "stop:\(form.from)",
                to: "stop:\(form.to)",
                at: PlannerFormat.toUnix(date: form.date, time: form.time),
                arriveBy: form.arriveBy,
                limit: Self.resultLimit,
                modes: modes
            )
        } else {
            query = nil
        }
        guard let query else { return }
        lastQuery = query
        runTask?.cancel()
        if !silent { result = .loading }
        runTask = Task { [weak self] in
            do {
                let plan = try await APIClient.shared.planJourney(query)
                guard !Task.isCancelled, let self else { return }
                self.result = .done(plan)
                AlertsStore.shared.evaluateTransfers(plan)
                if plan.mode == .now { self.startRefresh() } else { self.stopRefresh() }
            } catch {
                guard !Task.isCancelled, !silent, let self else { return }
                self.result = .error(Self.message(for: error))
            }
        }
    }

    private static func message(for error: Error) -> String {
        if let planError = error as? JourneyPlanError { return planError.message }
        if error is URLError {
            return "Nem sikerült elérni a szervert. Ellenőrizd a kapcsolatot, és próbáld újra."
        }
        return "Ismeretlen hiba történt."
    }

    // MARK: - Live refresh

    /// A live plan is refreshed every minute: delays and transfer odds move.
    private func startRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.liveRefresh)
                guard !Task.isCancelled, let self, self.isActive else { continue }
                self.run(silent: true)
            }
        }
    }

    private func stopRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// The scene is in the foreground (the web checks `visibilityState`).
    var isActive = true

    deinit {
        runTask?.cancel()
        refreshTask?.cancel()
        placesTask?.cancel()
    }
}

/// The regional coverage: the old Borsod-Abaúj-Zemplén county plus the
/// Füzesabony rail junction (`@mvk/core/transit/region`).
enum PlannerRegion {
    private static let polygon: [(Double, Double)] = [
        (48.3, 20.08), (48.3, 20.36), (48.47, 20.48), (48.56, 20.75), (48.55, 21.1), (48.52, 21.25), (48.57, 21.45),
        (48.41, 21.7), (48.38, 22.12), (48.25, 21.93), (48.18, 21.7), (48.1, 21.42), (48.0, 21.1), (47.88, 21.09),
        (47.64, 20.88), (47.7, 20.6), (47.7, 20.35), (47.95, 20.47), (48.08, 20.45), (48.12, 20.2), (48.2, 20.06),
    ]

    static func contains(lat: Double, lon: Double) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let (yi, xi) = polygon[i]
            let (yj, xj) = polygon[j]
            if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }
}
