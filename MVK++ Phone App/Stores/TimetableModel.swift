//
//  TimetableModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// Which runs the timetable lists: every enabled mode, or one group. Synced
/// across devices under the web's `mvk_pref_tt_group` key.
enum TimetableGroup: String, CaseIterable, Identifiable {
    case all, mvk, coach, rail

    static let preferenceKey = "mvk_pref_tt_group"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Mind"
        case .mvk: return "MVK"
        case .coach: return "Volán"
        case .rail: return "Vonat"
        }
    }

    var title: String {
        switch self {
        case .all: return ""
        case .mvk: return "MVK busz és villamos"
        case .coach: return "Volán helyközi busz"
        case .rail: return "Vonat"
        }
    }

    var modes: [TransitMode] {
        switch self {
        case .all: return []
        case .mvk: return [.bus, .tram]
        case .coach: return [.coach]
        case .rail: return [.rail]
        }
    }

    static func of(_ route: TimetableRoute) -> TimetableGroup {
        switch route.transitMode {
        case .coach: return .coach
        case .rail: return .rail
        case .tram, .bus: return .mvk
        }
    }

    var order: Int {
        switch self {
        case .mvk: return 0
        case .coach: return 1
        case .rail: return 2
        case .all: return 3
        }
    }
}

/// The timetable's state: the chosen service day, the routes running on it,
/// the open route and direction, its board, and the selected run. A port of
/// the web `TimetableView`'s state, with the trip journal and cancellations
/// kept live from the server.
@MainActor
final class TimetableModel: ObservableObject {

    @Published private(set) var routes: [TimetableRoute] = []
    @Published private(set) var routesError: String?
    /// The list on screen was read off the downloaded pack, not the gateway.
    @Published private(set) var isOffline = false

    @Published var selectedRouteId: String?
    @Published var selectedDir = ""
    @Published private(set) var table: TimetableResponse?
    @Published private(set) var isTableOffline = false
    @Published private(set) var tableLoading = false
    @Published private(set) var tableError = false
    @Published private(set) var selectedTrip: TimetableTrip?

    @Published var group: TimetableGroup {
        didSet { LocalStore.shared.setJSON(TimetableGroup.preferenceKey, group.rawValue) }
    }

    /// Seconds since the service day's midnight (24:xx after midnight), ticked every 15 s.
    @Published private(set) var nowSec: Int
    @Published private(set) var date: String

    let journal = TripJournalFeed()
    let cancelled = CancelledTripsFeed()

    private(set) var minIso: String?
    private(set) var maxIso: String?
    private let mountDay: String
    private var pendingTripId: String?
    private var selectedTripIntent: String?
    private var routesTask: Task<Void, Never>?
    private var tableTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var modesKey = TransitMode.param()

    init() {
        let today = Self.serviceNow().iso
        date = today
        mountDay = today
        nowSec = Self.serviceNow().secOfDay
        group = LocalStore.shared.json(TimetableGroup.preferenceKey, as: String.self).flatMap(TimetableGroup.init(rawValue:)) ?? .all

        let restored = ViewStateStore.initialTimetableView()
        selectedRouteId = restored?.routeId
        selectedDir = restored?.dir ?? ""
        pendingTripId = restored?.tripId
        selectedTripIntent = restored?.tripId

        journal.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        cancelled.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)

        // Opening may have used the device clock; once the server's arrives and
        // the rider has not paged away, follow the server's today.
        RealtimeClient.shared.$clockVersion
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.followServerToday() }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3($selectedRouteId, $selectedDir, $selectedTrip)
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { routeId, dir, trip in
                ViewStateStore.save(ViewStateStore.TimetableView(routeId: routeId, dir: dir, tripId: trip?.tripId))
            }
            .store(in: &cancellables)
    }

    static func serviceNow() -> ServiceClock {
        ServiceClock.at(Int(RealtimeClient.shared.serverNow))
    }

    static func todayIso() -> String { serviceNow().iso }

    // MARK: - Derived

    var isToday: Bool { date == Self.todayIso() }
    var day: DayRelation { TripStatus.dayRelation(date, todayIso: Self.todayIso()) }
    var ymd: String { ServiceClock.isoToYmd(date) }

    var selectedRoute: TimetableRoute? {
        guard let selectedRouteId else { return nil }
        return routes.first { $0.id == selectedRouteId }
    }

    var enabledModes: [TransitMode] { TransitMode.enabled() }

    /// "Mind" plus each group with at least one enabled mode.
    var groups: [TimetableGroup] {
        let modes = enabledModes
        return TimetableGroup.allCases.filter { $0 == .all || $0.modes.contains(where: modes.contains) }
    }

    var activeGroup: TimetableGroup { groups.contains(group) ? group : .all }

    func visibleRoutes(query: String) -> [TimetableRoute] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let active = activeGroup
        let inGroup = active == .all ? routes : routes.filter { TimetableGroup.of($0) == active }
        let sorted = inGroup.enumerated()
            .sorted { lhs, rhs in
                let a = TimetableGroup.of(lhs.element).order, b = TimetableGroup.of(rhs.element).order
                return a == b ? lhs.offset < rhs.offset : a < b
            }
            .map(\.element)
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { route in
            route.short.containsNormalized(needle)
                || route.long.containsNormalized(needle)
                || (route.operator?.containsNormalized(needle) ?? false)
                || route.directions.contains { $0.headsign.containsNormalized(needle) }
        }
    }

    var cancelledCountByRoute: [String: Int] {
        cancelled.trips.reduce(into: [:]) { counts, trip in
            guard !trip.routeId.isEmpty else { return }
            counts[trip.routeId, default: 0] += 1
        }
    }

    /// The button's counter is always about today, like the sheet it opens.
    var todayCancelledCount: Int { isToday ? cancelled.ids.count : 0 }

    /// „péntek” — the weekday, spelled out.
    var weekdayLabel: String {
        guard let parsed = Self.parse(date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: parsed)
    }

    /// „2026. nov. 14.” — the date field's label.
    var dateFieldLabel: String { Self.fieldLabel(date) }

    static func fieldLabel(_ iso: String) -> String {
        guard let parsed = parse(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: parsed)
    }

    /// Noon UTC of an ISO day, so weekday maths never slips across a zone.
    static func parse(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    // MARK: - Date

    func setRange(minIso: String?, maxIso: String?) {
        guard minIso != self.minIso || maxIso != self.maxIso else { return }
        self.minIso = minIso
        self.maxIso = maxIso
        setDate(clamp(date))
    }

    func setDate(_ iso: String) {
        let next = clamp(iso)
        guard next != date else { return }
        date = next
        reloadDay()
    }

    func shiftDate(by days: Int) {
        let next = ServiceClock.shiftIso(date, by: days)
        if let minIso, next < minIso { return }
        if let maxIso, next > maxIso { return }
        setDate(next)
    }

    var canGoBack: Bool { minIso.map { date > $0 } ?? true }
    var canGoForward: Bool { maxIso.map { date < $0 } ?? true }

    private func clamp(_ iso: String) -> String {
        if let minIso, iso < minIso { return minIso }
        if let maxIso, iso > maxIso { return maxIso }
        return iso
    }

    private func followServerToday() {
        let today = Self.todayIso()
        guard today != mountDay, date == mountDay else { return }
        setDate(today)
    }

    // MARK: - Lifecycle

    func start() {
        if clockTask == nil {
            clockTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    self?.nowSec = Self.serviceNow().secOfDay
                }
            }
        }
        let modes = TransitMode.param()
        if routes.isEmpty || modes != modesKey {
            modesKey = modes
            reloadDay()
        } else {
            refreshFeeds()
        }
    }

    func stop() {
        clockTask?.cancel()
        clockTask = nil
        journal.pause()
        cancelled.pause()
    }

    private func reloadDay() {
        refreshFeeds()
        loadRoutes()
        loadTable()
    }

    private func refreshFeeds() {
        cancelled.set(ymd: ymd, isToday: isToday)
        journal.set(ymd: ymd, pollInterval: day == .today ? 60 : 0)
    }

    private func loadRoutes() {
        routesTask?.cancel()
        let ymd = self.ymd
        let modes = modesKey
        routesTask = Task { [weak self] in
            do {
                let response = try await APIClient.shared.timetableRoutes(date: ymd, modes: modes)
                guard !Task.isCancelled, let self, self.ymd == ymd else { return }
                self.routes = response.routes
                self.routesError = nil
                self.isOffline = false
            } catch {
                guard !Task.isCancelled, let self, self.ymd == ymd else { return }
                if let stored = OfflineScheduleStore.timetableRoutes(ymd: ymd), !stored.routes.isEmpty {
                    self.routes = stored.routes
                    self.routesError = nil
                    self.isOffline = true
                } else {
                    self.isOffline = false
                    self.routesError = OfflineScheduleStore.manifest.isEmpty
                        ? error.localizedDescription
                        : "Erre a napra nincs letöltött menetrend, és a szerver sem érhető el."
                }
            }
        }
    }

    // MARK: - Route, direction, run

    func selectRoute(_ route: TimetableRoute) {
        let withService = route.directions.first { $0.tripsToday > 0 } ?? route.directions.first
        open(routeId: route.id, dir: withService?.dir ?? "")
    }

    func open(routeId: String, dir: String) {
        guard routeId != selectedRouteId || dir != selectedDir else { return }
        selectedRouteId = routeId
        selectedDir = dir
        loadTable()
    }

    func selectDir(_ dir: String) {
        guard dir != selectedDir else { return }
        selectedDir = dir
        loadTable()
    }

    func closeRoute() {
        selectedRouteId = nil
        tableTask?.cancel()
        table = nil
        chooseTrip(nil)
    }

    /// The intent is noted at selection time, not after: a reload and a day
    /// change can land in the same turn, and the run must survive both.
    func chooseTrip(_ trip: TimetableTrip?) {
        selectedTripIntent = trip?.tripId
        selectedTrip = trip
    }

    func toggleTrip(_ trip: TimetableTrip) {
        chooseTrip(selectedTrip?.tripId == trip.tripId ? nil : trip)
    }

    func retryTable() {
        loadTable()
    }

    /// A run picked from the disruption summary: today, its route and direction, the run selected.
    func openTrip(tripId: String, routeId: String, dir: String) {
        let today = Self.todayIso()
        if date == today, selectedRouteId == routeId, selectedDir == dir, let table {
            if let hit = table.trips.first(where: { $0.tripId == tripId }) { chooseTrip(hit) }
            return
        }
        pendingTripId = tripId
        selectedRouteId = routeId
        selectedDir = dir
        if date != today {
            date = clamp(today)
            reloadDay()
        } else {
            loadTable()
        }
    }

    private func loadTable() {
        tableTask?.cancel()
        guard let routeId = selectedRouteId else {
            table = nil
            return
        }
        let dir = selectedDir
        let ymd = self.ymd
        tableLoading = true
        tableError = false
        if pendingTripId == nil { pendingTripId = selectedTripIntent }
        selectedTrip = nil

        tableTask = Task { [weak self] in
            do {
                let response = try await APIClient.shared.timetable(routeId: routeId, dir: dir, date: ymd)
                guard !Task.isCancelled, let self else { return }
                self.apply(response, offline: false)
            } catch {
                guard !Task.isCancelled, let self else { return }
                if let stored = OfflineScheduleStore.timetable(routeId: routeId, dir: dir, ymd: ymd) {
                    self.apply(stored, offline: true)
                } else {
                    self.table = nil
                    self.tableError = true
                    self.tableLoading = false
                }
            }
        }
    }

    private func apply(_ response: TimetableResponse, offline: Bool) {
        table = response
        isTableOffline = offline
        tableLoading = false
        guard let pending = pendingTripId else { return }
        pendingTripId = nil
        if let hit = response.trips.first(where: { $0.tripId == pending }) { chooseTrip(hit) }
    }

    deinit {
        clockTask?.cancel()
        routesTask?.cancel()
        tableTask?.cancel()
    }
}
