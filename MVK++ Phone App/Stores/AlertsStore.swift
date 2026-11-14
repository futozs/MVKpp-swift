//
//  AlertsStore.swift
//  MVK++ Phone App
//

import BackgroundTasks
import Combine
import Foundation
import UserNotifications

/// The special alerts on this device (web `lib/alerts.ts`): "indulj most"
/// with the walking time, a traffic jam ahead of the bus, a transfer at risk.
/// The server's push watch is the source; here is what the rider switched on,
/// and whether the push registration worked — without it the app speaks up
/// itself, while open and from background refresh.
struct AlertWatch: Codable, Hashable, Identifiable {
    /// Unique within a stop: `leave:<trip>`, `traffic`, `transfer:<trip>`, `commute:<…>`.
    var slot: String
    /// "leave", "traffic" or "transfer".
    var kind: String
    var stopId: String
    var stopName: String
    var tripId: String?
    var routeShorts: [String]?
    /// Recurring: daily at this minute of the day.
    var schedMin: Int?
    var params: [String: AlertParam]?
    var pushRegistered: Bool
    var notifiedTripIds: [String]?
    /// Unix milliseconds, as on the web.
    var createdAt: Double

    var id: String { "\(stopId)|\(slot)" }

    var walkS: Double { max(0, min(3600, params?["walkS"]?.number ?? 0)) }
}

/// A param value as the web stores it (numbers, strings, flags, arrays of day numbers).
enum AlertParam: Codable, Hashable {
    case number(Double)
    case string(String)
    case numbers([Double])
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .numbers(try container.decode([Double].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .numbers(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    var number: Double? { if case .number(let value) = self { return value } else { return nil } }
    var string: String? { if case .string(let value) = self { return value } else { return nil } }

    var any: Any {
        switch self {
        case .number(let value): return value
        case .string(let value): return value
        case .numbers(let value): return value
        case .bool(let value): return value
        }
    }
}

@MainActor
final class AlertsStore: ObservableObject {
    static let shared = AlertsStore()

    static let key = "mvk_alert_watches"

    @Published private(set) var alerts: [AlertWatch]
    private var settingsObserver: NSObjectProtocol?

    private init() {
        alerts = LocalStore.shared.json(Self.key, as: [AlertWatch].self) ?? []
        // The main switch or "Ne zavarj" withdrew the planned alarms.
        settingsObserver = NotificationCenter.default.addObserver(forName: .mvkNotificationSettingsChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in AlertsStore.shared.refresh() }
        }
    }

    private func write(_ list: [AlertWatch]) {
        alerts = list
        LocalStore.shared.setJSON(Self.key, list)
    }

    private func update(_ id: String, _ change: (inout AlertWatch) -> Void) {
        var list = alerts
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[index])
        write(list)
    }

    func find(stopId: String, slot: String) -> AlertWatch? {
        alerts.first { $0.stopId == stopId && $0.slot == slot }
    }

    func has(stopId: String, slot: String) -> Bool {
        find(stopId: stopId, slot: slot) != nil
    }

    func alert(stopId: String, slotPrefix: String) -> AlertWatch? {
        alerts.first { $0.stopId == stopId && $0.slot.hasPrefix(slotPrefix) }
    }

    struct AddResult {
        let ok: Bool
        let push: Bool
        var reason: String?

        /// Why no alert comes while the app is closed (the "push nélkül" note).
        var noPushNote: String {
            reason.map { "Csak nyitott appnál szólok: \($0)" } ?? "Push nélkül csak akkor szólok, ha nyitva van az app."
        }
    }

    /// Switching on: asks for permission, saves a push watch on the server;
    /// without push the app tells the rider itself.
    func add(slot: String, kind: String, stopId: String, stopName: String, tripId: String? = nil, routeShorts: [String]? = nil, schedMin: Int? = nil, params: [String: AlertParam]? = nil) async -> AddResult {
        let granted = await NotificationCenterStore.shared.requestPermission()
        guard granted else {
            let denied = NotificationCenterStore.shared.authorization == .denied
            return AddResult(ok: false, push: false, reason: denied ? "Az értesítések le vannak tiltva az iPhone beállításaiban." : "Az értesítéshez engedély kell.")
        }
        PushService.shared.permissionGranted()
        let diag = await PushService.shared.registerWatch(PushService.WatchConfig(
            stopId: stopId, stopName: stopName, thresholdMin: 5, routeShorts: routeShorts, tripId: tripId,
            schedMin: schedMin, slot: slot, kind: kind, params: params?.mapValues(\.any)
        ))
        let alert = AlertWatch(
            slot: slot, kind: kind, stopId: stopId, stopName: stopName, tripId: tripId, routeShorts: routeShorts,
            schedMin: schedMin, params: params, pushRegistered: diag.ok, notifiedTripIds: nil,
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        write(alerts.filter { $0.id != alert.id } + [alert])
        if !alert.pushRegistered { LocalAlertEvaluator.planRecurring(alert) }
        BackgroundRefresh.schedule()
        return AddResult(ok: true, push: diag.ok, reason: diag.ok ? nil : diag.reason)
    }

    func remove(stopId: String, slot: String) async {
        write(alerts.filter { !($0.stopId == stopId && $0.slot == slot) })
        LocalAlertEvaluator.cancelPending(stopId: stopId, slot: slot)
        await PushService.shared.unregisterWatch(stopId: stopId, slot: slot)
    }

    func reRegister(_ alert: AlertWatch) async {
        let diag = await PushService.shared.registerWatch(PushService.WatchConfig(
            stopId: alert.stopId, stopName: alert.stopName, thresholdMin: 5, routeShorts: alert.routeShorts,
            tripId: alert.tripId, schedMin: alert.schedMin, slot: alert.slot, kind: alert.kind,
            params: alert.params?.mapValues(\.any)
        ))
        update(alert.id) { $0.pushRegistered = diag.ok }
        if diag.ok { LocalAlertEvaluator.cancelPending(stopId: alert.stopId, slot: alert.slot) }
    }

    /// A local (push-less) notification once per trip; true if it spoke now.
    @discardableResult
    func notifyLocallyOnce(stopId: String, slot: String, tripId: String, title: String, body: String) -> Bool {
        guard let alert = find(stopId: stopId, slot: slot), !alert.pushRegistered,
              !(alert.notifiedTripIds ?? []).contains(tripId) else { return false }
        let center = NotificationCenterStore.shared
        // The main switch and "Ne zavarj" apply to local alerts too.
        guard center.isAuthorized, center.settings.enabled, !center.isWithinDnd() else { return false }
        let id = LocalAlertEvaluator.identifier(stopId: stopId, slot: slot, tripId: tripId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        LocalAlertEvaluator.post(id: "\(id)-now", title: title, body: body, trigger: nil, stopId: stopId)
        update(alert.id) { $0.notifiedTripIds = Array(($0.notifiedTripIds ?? []).suffix(20)) + [tripId] }
        return true
    }

    /// Expired one-off (trip-bound) alerts go; the server drops them too.
    func prune(maxAge: TimeInterval = 4 * 3600) {
        let now = Date().timeIntervalSince1970 * 1000
        let keep = alerts.filter { $0.schedMin != nil || $0.kind == "traffic" || now - $0.createdAt < maxAge * 1000 }
        if keep.count != alerts.count { write(keep) }
    }

    // MARK: - Local fallback

    /// Every fresh board of a stop: the push-less alerts there are checked
    /// on the phone, as the web does while the page is open.
    func boardUpdated(stopId: String, arrivals: [ArrivalItem]) {
        let pending = alerts.filter { $0.stopId == stopId && !$0.pushRegistered && $0.kind != "transfer" }
        guard !pending.isEmpty else { return }
        LocalAlertEvaluator.evaluate(pending, arrivals: arrivals, now: RealtimeClient.shared.serverNow)
    }

    /// Drops expired one-shot alerts and re-plans the week ahead of the
    /// push-less recurring ones.
    func refresh() {
        prune()
        for alert in alerts where alert.schedMin != nil && !alert.pushRegistered {
            LocalAlertEvaluator.planRecurring(alert)
        }
    }

    /// A fresh plan from the planner: a push-less watched transfer whose
    /// chance has collapsed is told once, with the next option.
    func evaluateTransfers(_ plan: JourneyPlanResponse) {
        guard plan.mode == .now, alerts.contains(where: { $0.kind == "transfer" && !$0.pushRegistered }) else { return }
        let now = RealtimeClient.shared.serverNow
        for trip in plan.trips {
            for check in trip.transferChecks {
                guard let toTrip = check.toTripId, let stopId = check.boardStopId,
                      let chance = check.chance, chance < LocalAlertEvaluator.transferAlertChance,
                      let leg = trip.legs.first(where: { $0.tripId == toTrip }), let sched = leg.schedDep else { continue }
                let depart = sched + (leg.prediction?.depDelayS ?? 0)
                guard depart >= now - 60, depart - now <= 3600 else { continue }
                let pct = Int((chance * 100).rounded())
                let fromRoute = check.fromRoute.map { HungarianText.withSuffix($0) + " " } ?? ""
                let toRoute = check.toRoute.map(HungarianText.withSuffix) ?? "csatlakozás"
                let late = check.marginSec < 0 ? "\(TripInsightText.minutes(-check.marginSec)) késéssel" : "épp csak"
                let fallback = check.fallback.map { " Ha lekésed: \($0.time)." } ?? ""
                notifyLocallyOnce(stopId: stopId, slot: "transfer:\(toTrip)", tripId: toTrip,
                                  title: "Veszélyben az átszállás (\(pct)% esély)",
                                  body: "A \(fromRoute)busz várhatóan \(late) ér ide a \(toRoute) indulásához \(check.at).\(fallback)")
            }
        }
    }
}

// MARK: - Local evaluation

/// What the server's push engine does for each alert kind (`push.ts`), run
/// on the phone for alerts the server cannot push (no APNs key, registration
/// failed). Transfers need the server's transfer outlook and are checked
/// against the planner's fresh plans instead.
@MainActor
enum LocalAlertEvaluator {
    static let transferAlertChance = 0.4
    private static let trafficAlertS = 150.0
    private static let trafficHorizonMin = 30
    private static let recurringWindowMin = 4

    /// Background refresh: each stop with a push-less alert is read once.
    static func run() async {
        AlertsStore.shared.prune()
        let pending = AlertsStore.shared.alerts.filter { !$0.pushRegistered && $0.kind != "transfer" }
        let local = LocalStore.shared
        for stopId in Set(pending.map(\.stopId)) {
            let items = [
                URLQueryItem(name: "stop", value: stopId),
                URLQueryItem(name: "limit", value: "40"),
                URLQueryItem(name: "modes", value: local.modesParam),
                URLQueryItem(name: "merge", value: local.stopMerge.rawValue),
            ]
            guard let board: StopArrivalsResponse = try? await APIClient.shared.request(path: "/live/arrivals", queryItems: items) else { continue }
            evaluate(pending.filter { $0.stopId == stopId }, arrivals: board.arrivals, now: board.now)
        }
    }

    static func evaluate(_ alerts: [AlertWatch], arrivals: [ArrivalItem], now: Double) {
        for alert in alerts {
            switch alert.kind {
            case "leave": evaluateLeave(alert, arrivals: arrivals, now: now)
            case "traffic": evaluateTraffic(alert, arrivals: arrivals)
            default: break
            }
        }
    }

    private static func relevant(_ alert: AlertWatch, arrivals: [ArrivalItem], now: Double) -> [ArrivalItem] {
        let routes = alert.routeShorts.flatMap { $0.isEmpty ? nil : $0 }
        let nowMin = BudapestClock.minute(now)
        return arrivals.filter { arrival in
            if let schedMin = alert.schedMin {
                if let routes, !routes.contains(arrival.route) { return false }
                let delayMin = Int((Double(arrival.delaySec ?? 0) / 60).rounded())
                let arrivalMin = ((nowMin + arrival.etaMin - delayMin) % 1440 + 1440) % 1440
                let distance = abs(arrivalMin - schedMin)
                return min(distance, 1440 - distance) <= recurringWindowMin
            }
            if let tripId = alert.tripId { return arrival.tripId == tripId }
            return routes.map { $0.contains(arrival.route) } ?? true
        }
    }

    private static func evaluateLeave(_ alert: AlertWatch, arrivals: [ArrivalItem], now: Double) {
        if alert.schedMin != nil, !isWatchDay(alert.params?["days"], iso: BudapestClock.serviceIso(now)) { return }
        let walkS = alert.walkS
        let store = AlertsStore.shared
        for arrival in relevant(alert, arrivals: arrivals, now: now) {
            let expected = CatchBus.expectedArrival(arrival, now: now)
            guard expected.at - now <= 3600 else { continue }
            let next = arrivals.first { !$0.isCancelled && $0.route == arrival.route && $0.tripId != arrival.tripId && Double($0.etaMin * 60) >= walkS }
            let nextText = next.map { " A következő \(HungarianText.withSuffix(arrival.route)): \($0.time)." } ?? ""
            if arrival.isCancelled {
                store.notifyLocallyOnce(stopId: alert.stopId, slot: alert.slot, tripId: arrival.tripId,
                    title: "\(busLabel(arrival)) kimarad",
                    body: "\(TransitIds.isRegional(arrival.tripId) ? "Törölték" : "Az MVK kihúzta") a \(arrival.time)-s menetet (\(alert.stopName)).\(nextText)")
                continue
            }
            let verdict = CatchBus.verdict(now: now, expected: expected.at, upper: expected.upper, walkS: walkS)
            let delay = delaySuffix(arrival.measuredDelaySec ?? arrival.delaySec)
            switch verdict.state {
            case .relax:
                schedule(alert, tripId: arrival.tripId, at: verdict.leaveAtUnix, now: now,
                         title: "Indulj most: \(busLabel(arrival)) \(TripInsightText.minutes(expected.at - verdict.leaveAtUnix)) múlva",
                         body: "\(alert.stopName) \(TripInsightText.minutes(walkS)) séta\(delay).")
            case .go, .run:
                let eta = TripInsightText.minutes(expected.at - now)
                store.notifyLocallyOnce(stopId: alert.stopId, slot: alert.slot, tripId: arrival.tripId,
                    title: verdict.state == .run ? "Siess! \(busLabel(arrival)) \(eta) múlva" : "Indulj most: \(busLabel(arrival)) \(eta) múlva",
                    body: "\(alert.stopName) \(TripInsightText.minutes(walkS)) séta\(verdict.state == .run ? ", csak futva éred el" : "")\(delay).")
            case .missed:
                store.notifyLocallyOnce(stopId: alert.stopId, slot: alert.slot, tripId: arrival.tripId,
                    title: "\(busLabel(arrival)): ezt már nem éred el",
                    body: "\(TripInsightText.minutes(expected.at - now)) múlva ér a \(alert.stopName) megállóba, a séta \(TripInsightText.minutes(walkS)).\(nextText)")
            }
        }
    }

    private static func evaluateTraffic(_ alert: AlertWatch, arrivals: [ArrivalItem]) {
        let routes = alert.routeShorts.flatMap { $0.isEmpty ? nil : $0 }
        for arrival in arrivals {
            guard let traffic = arrival.trafficAhead, traffic.excessS >= trafficAlertS,
                  !arrival.isCancelled, arrival.etaMin <= trafficHorizonMin else { continue }
            if let routes, !routes.contains(arrival.route) { continue }
            AlertsStore.shared.notifyLocallyOnce(stopId: alert.stopId, slot: alert.slot, tripId: arrival.tripId,
                title: "Dugó: \(busLabel(arrival)) kb. +\(TripInsightText.minutes(traffic.excessS))",
                body: "\(traffic.fromName) → \(traffic.toName) között beállt a forgalom kb. \(arrival.etaMin) perc múlva ér a \(alert.stopName) megállóba.")
        }
    }

    // MARK: - Delivery

    static func identifier(stopId: String, slot: String, tripId: String) -> String {
        "\(prefix(stopId: stopId, slot: slot))\(tripId)"
    }

    private static func prefix(stopId: String, slot: String) -> String {
        "mvk-alert-\(stopId)-\(slot)-"
    }

    static func post(id: String, title: String, body: String, trigger: UNNotificationTrigger?, stopId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "mvk-stop-\(stopId)"
        content.userInfo = ["stopId": stopId]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// While it is still early, the "Indulj most" is aimed at the moment to
    /// leave, so it arrives with the app closed too; each fresh board re-aims it.
    private static func schedule(_ alert: AlertWatch, tripId: String, at unix: Double, now: Double, title: String, body: String) {
        let lead = unix - now
        let center = NotificationCenterStore.shared
        guard lead > 0, center.settings.enabled, !(alert.notifiedTripIds ?? []).contains(tripId),
              !center.isWithinDnd(now: Date().addingTimeInterval(lead)) else { return }
        post(id: identifier(stopId: alert.stopId, slot: alert.slot, tripId: tripId), title: title, body: body,
             trigger: UNTimeIntervalNotificationTrigger(timeInterval: lead, repeats: false), stopId: alert.stopId)
        if alert.schedMin != nil {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["\(prefix(stopId: alert.stopId, slot: alert.slot))day-\(BudapestClock.serviceIso(now))"]
            )
        }
    }

    /// A push-less recurring alert, planned for the next seven days it
    /// applies to: the scheduled minute less the walk and the safety margin.
    /// A live board on the day replaces that day's entry with an exact one.
    static func planRecurring(_ alert: AlertWatch) {
        guard let schedMin = alert.schedMin, alert.kind == "leave", NotificationCenterStore.shared.settings.enabled else { return }
        let leadMin = Int(((alert.walkS + CatchBus.safetyS + CatchBus.earlyDefaultS) / 60).rounded(.up))
        let route = alert.routeShorts?.first.map(HungarianText.withSuffix) ?? ""
        let now = Date().timeIntervalSince1970
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BudapestClock.timeZone

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let iso = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            guard isWatchDay(alert.params?["days"], iso: iso) else { continue }
            var fire = parts
            let minute = ((schedMin - leadMin) % 1440 + 1440) % 1440
            fire.hour = minute / 60
            fire.minute = minute % 60
            fire.timeZone = BudapestClock.timeZone
            guard let date = calendar.date(from: fire), date.timeIntervalSince1970 > now,
                  !NotificationCenterStore.shared.isWithinDnd(now: date) else { continue }
            post(
                id: "\(prefix(stopId: alert.stopId, slot: alert.slot))day-\(iso)",
                title: "Indulj most: \(route) \(BudapestClock.hm(minute: schedMin))",
                body: "\(alert.stopName) \(TripInsightText.minutes(alert.walkS)) séta.",
                trigger: UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false),
                stopId: alert.stopId
            )
        }
    }

    static func cancelPending(stopId: String, slot: String) {
        let prefix = prefix(stopId: stopId, slot: slot)
        Task {
            let center = UNUserNotificationCenter.current()
            let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Text

    /// „21-es busz (1644)”, „1-es villamos”, „5139-es vonat (IC TOKAJ)”.
    static func busLabel(_ arrival: ArrivalItem) -> String {
        if arrival.mode == .rail {
            return "\(HungarianText.withSuffix(arrival.trainNo ?? arrival.route)) vonat\(arrival.trainName.map { " (\($0))" } ?? "")"
        }
        let plate = { (id: String) in id.replacingOccurrences(of: "hkir:hkir_", with: "") }
        let vehicle: String?
        if let id = arrival.vehicle?.id {
            vehicle = plate(id)
        } else if let predicted = arrival.predictedVehicle {
            vehicle = predicted.method == "loop" ? plate(predicted.id) : "~\(plate(predicted.id))"
        } else {
            vehicle = nil
        }
        return "\(HungarianText.withSuffix(arrival.route)) \(arrival.mode == .tram ? "villamos" : "busz")\(vehicle.map { " (\($0))" } ?? "")"
    }

    private static func delaySuffix(_ delaySec: Int?) -> String {
        guard let delaySec, abs(delaySec) >= 60 else { return "" }
        let minutes = Int((Double(abs(delaySec)) / 60).rounded())
        return delaySec > 0 ? " (\(minutes) perc késés)" : " (\(minutes) perccel korábban)"
    }

    /// Whether a recurring alert applies on a day: every day, workdays or
    /// weekends, or listed weekdays (a workday habit never on a weekend).
    static func isWatchDay(_ days: AlertParam?, iso: String) -> Bool {
        let dow = BudapestClock.isoDow(iso)
        let kind = dow >= 6 ? "weekend" : "workday"
        switch days {
        case .none: return true
        case .string(let value): return value == "all" || value == kind
        case .numbers(let list):
            let workdayHabit = list.allSatisfy { $0 <= 5 }
            return list.contains(Double(dow)) && !(workdayHabit && kind != "workday")
        default: return true
        }
    }
}

// MARK: - Background refresh

/// Keeps local alarms honest while the app is closed: watched stops whose
/// alerts the server cannot push are re-read and their alarms rescheduled.
enum BackgroundRefresh {
    static let identifier = "hu.futozs.mvk.watch-refresh"

    @MainActor
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            let work = Task { @MainActor in
                await runOnce()
                schedule()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    @MainActor
    static func schedule() {
        let needsLocal = NotificationCenterStore.shared.watches.values.contains { $0.pushRegistered != true }
            || AlertsStore.shared.alerts.contains { !$0.pushRegistered }
        guard needsLocal else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Arrival alarms for local-only watches, then the special alerts.
    @MainActor
    static func runOnce() async {
        let center = NotificationCenterStore.shared
        await center.refreshAuthorization()
        let local = LocalStore.shared
        for watch in center.watches.values where watch.pushRegistered != true {
            let items = [
                URLQueryItem(name: "stop", value: watch.stopId),
                URLQueryItem(name: "limit", value: "40"),
                URLQueryItem(name: "modes", value: local.modesParam),
                URLQueryItem(name: "merge", value: local.stopMerge.rawValue),
            ]
            guard let board: StopArrivalsResponse = try? await APIClient.shared.request(path: "/live/arrivals", queryItems: items) else { continue }
            center.scheduleAlarm(stopId: watch.stopId, stopName: watch.stopName, arrivals: board.arrivals)
        }
        await LocalAlertEvaluator.run()
    }
}
