//
//  AlertWatchStore.swift
//  MVK++ Phone App
//

import Combine
import Foundation
import UserNotifications

/// A JSON value, for the web shape's free-form `params`.
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

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

/// One special alert on this device — the web app's `lib/alerts` shape,
/// stored under the same `mvk_alert_watches` key so cloud sync can carry it.
struct AlertWatch: Codable, Hashable {
    /// Unique within the stop: `leave:<trip>`, `traffic`, `transfer:<trip>`, `commute:<…>`.
    var slot: String
    /// `leave`, `traffic` or `transfer`.
    var kind: String
    var stopId: String
    var stopName: String
    var tripId: String?
    var routeShorts: [String]?
    /// Recurring: the scheduled minute of the day.
    var schedMin: Int?
    var params: [String: AlertParam]?
    var pushRegistered: Bool
    var notifiedTripIds: [String]?
    /// Unix milliseconds, as on the web.
    var createdAt: Double

    var walkS: Double { max(0, min(3600, params?["walkS"]?.number ?? 0)) }
}

/// „Indulj most”, congestion ahead, a commute reminder: what the rider
/// switched on, and the notifications behind it.
///
/// The web registers these as server pushes. Here the phone schedules them
/// itself: each board refresh re-aims a pending notification at the moment
/// to leave, so it still arrives with the app closed, and a recurring
/// (commute) alert is planned a week ahead on the days it applies.
@MainActor
final class AlertWatchStore: ObservableObject {
    static let shared = AlertWatchStore()

    struct AddResult {
        let ok: Bool
        /// Arrives with the app closed (the web's "push" result).
        let push: Bool
        var reason: String?

        /// Why it only works while the app is open.
        var noPushNote: String {
            reason.map { "Csak nyitott appnál szólok: \($0)" } ?? "Push nélkül csak akkor szólok, ha nyitva van az app."
        }
    }

    static let storageKey = "mvk_alert_watches"
    private static let trafficAlertS = 150.0
    private static let trafficHorizonMin = 30
    private static let recurringWindowMin = 4
    private static let oneShotMaxAge: TimeInterval = 4 * 3600

    @Published private(set) var alerts: [AlertWatch] = []

    private init() {
        alerts = Self.read()
        prune()
    }

    func has(stopId: String, slot: String) -> Bool {
        alerts.contains { $0.stopId == stopId && $0.slot == slot }
    }

    func alert(stopId: String, slotPrefix: String) -> AlertWatch? {
        alerts.first { $0.stopId == stopId && $0.slot.hasPrefix(slotPrefix) }
    }

    func add(_ alert: AlertWatch) async -> AddResult {
        let store = NotificationCenterStore.shared
        guard await store.requestPermission() else {
            await store.refreshAuthorization()
            return AddResult(
                ok: false,
                push: false,
                reason: store.authorization == .denied ? "Az értesítések le vannak tiltva a rendszerbeállításokban." : "Az értesítéshez engedély kell."
            )
        }
        var stored = alert
        stored.pushRegistered = alert.kind != "traffic"
        stored.createdAt = Date().timeIntervalSince1970 * 1000
        alerts = alerts.filter { !($0.stopId == alert.stopId && $0.slot == alert.slot) } + [stored]
        persist()
        if stored.schedMin != nil { planRecurring(stored) }
        return AddResult(ok: true, push: stored.pushRegistered)
    }

    func remove(stopId: String, slot: String) {
        alerts.removeAll { $0.stopId == stopId && $0.slot == slot }
        persist()
        let prefix = Self.identifierPrefix(stopId: stopId, slot: slot)
        Task {
            let center = UNUserNotificationCenter.current()
            let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Evaluation

    /// Called on every board refresh for a stop.
    func boardUpdated(stopId: String, stopName: String, arrivals: [ArrivalItem]) {
        let mine = alerts.filter { $0.stopId == stopId }
        guard !mine.isEmpty, NotificationCenterStore.shared.settings.enabled else { return }
        let now = RealtimeClient.shared.serverNow
        for alert in mine {
            switch alert.kind {
            case "leave": evaluateLeave(alert, arrivals: arrivals, now: now)
            case "traffic": evaluateTraffic(alert, arrivals: arrivals)
            default: break
            }
        }
    }

    private func relevant(_ alert: AlertWatch, arrivals: [ArrivalItem], now: Double) -> [ArrivalItem] {
        let filter = alert.routeShorts.flatMap { $0.isEmpty ? nil : $0 }
        let nowMin = BudapestClock.minute(now)
        return arrivals.filter { arrival in
            if let schedMin = alert.schedMin {
                if let filter, !filter.contains(arrival.route) { return false }
                let delayMin = Int((Double(arrival.delaySec ?? 0) / 60).rounded())
                let arrivalMin = ((nowMin + arrival.etaMin - delayMin) % 1440 + 1440) % 1440
                let distance = abs(arrivalMin - schedMin)
                return min(distance, 1440 - distance) <= Self.recurringWindowMin
            }
            if let tripId = alert.tripId { return arrival.tripId == tripId }
            return filter.map { $0.contains(arrival.route) } ?? true
        }
    }

    private func evaluateLeave(_ alert: AlertWatch, arrivals: [ArrivalItem], now: Double) {
        if alert.schedMin != nil, !Self.isWatchDay(alert.params?["days"], iso: BudapestClock.serviceIso(now)) { return }
        let walkS = alert.walkS
        for arrival in relevant(alert, arrivals: arrivals, now: now) {
            let expected = CatchBus.expectedArrival(arrival, now: now)
            guard expected.at - now <= 3600 else { continue }
            if arrival.isCancelled {
                let next = arrivals.first { !$0.isCancelled && $0.route == arrival.route && $0.etaMin * 60 >= Int(walkS) }
                deliverOnce(alert, tripId: arrival.tripId, tag: "cancelled",
                            title: "\(Self.busLabel(arrival)) kimarad",
                            body: "\(TransitIds.isRegional(arrival.tripId) ? "Törölték" : "Az MVK kihúzta") a \(arrival.time)-s menetet (\(alert.stopName)).\(next.map { " A következő \(HungarianText.withSuffix(arrival.route)): \($0.time)." } ?? "")")
                continue
            }
            let verdict = CatchBus.verdict(now: now, expected: expected.at, upper: expected.upper, walkS: walkS)
            let delay = Self.delaySuffix(arrival.measuredDelaySec ?? arrival.delaySec)
            switch verdict.state {
            case .relax:
                let eta = TripInsightText.minutes(expected.at - verdict.leaveAtUnix)
                schedule(alert, tripId: arrival.tripId, at: verdict.leaveAtUnix, now: now,
                         title: "Indulj most: \(Self.busLabel(arrival)) \(eta) múlva",
                         body: "\(alert.stopName) \(TripInsightText.minutes(walkS)) séta\(delay).")
            case .go, .run:
                let eta = TripInsightText.minutes(expected.at - now)
                deliverOnce(alert, tripId: arrival.tripId, tag: "leave",
                            title: verdict.state == .run ? "Siess! \(Self.busLabel(arrival)) \(eta) múlva" : "Indulj most: \(Self.busLabel(arrival)) \(eta) múlva",
                            body: "\(alert.stopName) \(TripInsightText.minutes(walkS)) séta\(verdict.state == .run ? ", csak futva éred el" : "")\(delay).")
            case .missed:
                guard !(alert.notifiedTripIds ?? []).contains("\(arrival.tripId)|leave") else { continue }
                let next = arrivals.first { !$0.isCancelled && $0.route == arrival.route && Double($0.etaMin * 60) >= walkS && $0.tripId != arrival.tripId }
                deliverOnce(alert, tripId: arrival.tripId, tag: "missed",
                            title: "\(Self.busLabel(arrival)): ezt már nem éred el",
                            body: "\(TripInsightText.minutes(expected.at - now)) múlva ér a \(alert.stopName) megállóba, a séta \(TripInsightText.minutes(walkS)).\(next.map { " A következő \(HungarianText.withSuffix(arrival.route)): \($0.time)." } ?? "")")
            }
        }
    }

    private func evaluateTraffic(_ alert: AlertWatch, arrivals: [ArrivalItem]) {
        let filter = alert.routeShorts.flatMap { $0.isEmpty ? nil : $0 }
        for arrival in arrivals {
            guard let traffic = arrival.trafficAhead, traffic.excessS >= Self.trafficAlertS,
                  !arrival.isCancelled, arrival.etaMin <= Self.trafficHorizonMin else { continue }
            if let filter, !filter.contains(arrival.route) { continue }
            deliverOnce(alert, tripId: arrival.tripId, tag: "traffic",
                        title: "Dugó: \(Self.busLabel(arrival)) kb. +\(TripInsightText.minutes(traffic.excessS))",
                        body: "\(traffic.fromName) → \(traffic.toName) között beállt a forgalom kb. \(arrival.etaMin) perc múlva ér a \(alert.stopName) megállóba.")
        }
    }

    // MARK: - Delivery

    private func deliverOnce(_ alert: AlertWatch, tripId: String, tag: String, title: String, body: String) {
        let key = "\(tripId)|\(tag)"
        guard !(alert.notifiedTripIds ?? []).contains(key), !NotificationCenterStore.shared.isWithinDnd() else { return }
        let id = "\(Self.identifierPrefix(stopId: alert.stopId, slot: alert.slot))\(tripId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        post(id: "\(id)-\(tag)", title: title, body: body, trigger: nil, stopId: alert.stopId)
        mark(alert, key: key)
    }

    private func schedule(_ alert: AlertWatch, tripId: String, at unix: Double, now: Double, title: String, body: String) {
        let lead = unix - now
        guard lead > 0 else { return }
        guard !NotificationCenterStore.shared.isWithinDnd(now: Date().addingTimeInterval(lead)) else { return }
        let id = "\(Self.identifierPrefix(stopId: alert.stopId, slot: alert.slot))\(tripId)"
        post(id: id, title: title, body: body, trigger: UNTimeIntervalNotificationTrigger(timeInterval: lead, repeats: false), stopId: alert.stopId)
        if alert.schedMin != nil {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["\(Self.identifierPrefix(stopId: alert.stopId, slot: alert.slot))day-\(BudapestClock.serviceIso(now))"]
            )
        }
    }

    private func post(id: String, title: String, body: String, trigger: UNNotificationTrigger?, stopId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "mvk-stop-\(stopId)"
        content.userInfo = ["url": "mvkpp://watch/\(stopId)"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func mark(_ alert: AlertWatch, key: String) {
        guard let index = alerts.firstIndex(where: { $0.stopId == alert.stopId && $0.slot == alert.slot }) else { return }
        alerts[index].notifiedTripIds = Array(((alerts[index].notifiedTripIds ?? []) + [key]).suffix(20))
        persist()
    }

    /// A recurring alert, planned for the next seven days it applies to: the
    /// scheduled minute less the walk and the safety margin. A live board
    /// on the day replaces that day's entry with an exact one.
    private func planRecurring(_ alert: AlertWatch) {
        guard let schedMin = alert.schedMin else { return }
        let prefix = Self.identifierPrefix(stopId: alert.stopId, slot: alert.slot)
        let leadMin = Int(((alert.walkS + CatchBus.safetyS + CatchBus.earlyDefaultS) / 60).rounded(.up))
        let route = alert.routeShorts?.first.map(HungarianText.withSuffix) ?? ""
        let now = Date().timeIntervalSince1970
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BudapestClock.timeZone

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            let iso = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            guard Self.isWatchDay(alert.params?["days"], iso: iso) else { continue }
            var fire = parts
            let minute = ((schedMin - leadMin) % 1440 + 1440) % 1440
            fire.hour = minute / 60
            fire.minute = minute % 60
            fire.timeZone = BudapestClock.timeZone
            guard let date = calendar.date(from: fire), date.timeIntervalSince1970 > now else { continue }
            post(
                id: "\(prefix)day-\(iso)",
                title: "Indulj most: \(route) \(BudapestClock.hm(minute: schedMin))",
                body: "\(alert.stopName) \(TripInsightText.minutes(alert.walkS)) séta.",
                trigger: UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false),
                stopId: alert.stopId
            )
        }
    }

    /// Re-plans the recurring alerts (the week ahead moves on) and drops
    /// expired one-shot ones.
    func refresh() {
        prune()
        for alert in alerts where alert.schedMin != nil { planRecurring(alert) }
    }

    private func prune() {
        let now = Date().timeIntervalSince1970 * 1000
        let keep = alerts.filter { $0.schedMin != nil || $0.kind == "traffic" || now - $0.createdAt < Self.oneShotMaxAge * 1000 }
        if keep.count != alerts.count {
            alerts = keep
            persist()
        }
    }

    // MARK: - Helpers

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

    private static func identifierPrefix(stopId: String, slot: String) -> String {
        "mvk-alert-\(stopId)-\(slot)-"
    }

    private static func read() -> [AlertWatch] {
        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: storageKey) ?? defaults.string(forKey: storageKey).map { Data($0.utf8) }
        guard let data else { return [] }
        return (try? JSONDecoder().decode([AlertWatch].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
