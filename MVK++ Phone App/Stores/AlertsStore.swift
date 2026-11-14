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
    var createdAt: Double

    var id: String { "\(stopId)|\(slot)" }
}

/// A param value as the web stores it (numbers, strings, arrays of day numbers).
enum AlertParam: Codable, Hashable {
    case number(Double)
    case text(String)
    case numbers([Double])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([Double].self) { self = .numbers(value) }
        else { self = .text(try container.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        case .numbers(let value): try container.encode(value)
        }
    }

    var number: Double? { if case .number(let value) = self { return value } else { return nil } }
    var text: String? { if case .text(let value) = self { return value } else { return nil } }

    var any: Any {
        switch self {
        case .number(let value): return value
        case .text(let value): return value
        case .numbers(let value): return value
        }
    }
}

@MainActor
final class AlertsStore: ObservableObject {
    static let shared = AlertsStore()

    private static let key = "mvk_alert_watches"

    @Published private(set) var alerts: [AlertWatch]

    private init() {
        alerts = LocalStore.shared.json(Self.key, as: [AlertWatch].self) ?? []
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

    struct AddResult {
        let ok: Bool
        let push: Bool
        var reason: String?
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
        let rest = alerts.filter { !($0.stopId == stopId && $0.slot == slot) }
        write(rest + [AlertWatch(
            slot: slot, kind: kind, stopId: stopId, stopName: stopName, tripId: tripId, routeShorts: routeShorts,
            schedMin: schedMin, params: params, pushRegistered: diag.ok, notifiedTripIds: nil,
            createdAt: Date().timeIntervalSince1970 * 1000
        )])
        BackgroundRefresh.schedule()
        return AddResult(ok: true, push: diag.ok, reason: diag.ok ? nil : diag.reason)
    }

    /// Why no alert comes while the app is closed (the "push nélkül" note).
    static func noPushNote(_ result: AddResult) -> String {
        result.reason.map { "Csak nyitott appnál szólok: \($0)" } ?? "Push nélkül csak akkor szólok, ha nyitva van az app."
    }

    func remove(stopId: String, slot: String) async {
        write(alerts.filter { !($0.stopId == stopId && $0.slot == slot) })
        await PushService.shared.unregisterWatch(stopId: stopId, slot: slot)
    }

    func reRegister(_ alert: AlertWatch) async {
        let diag = await PushService.shared.registerWatch(PushService.WatchConfig(
            stopId: alert.stopId, stopName: alert.stopName, thresholdMin: 5, routeShorts: alert.routeShorts,
            tripId: alert.tripId, schedMin: alert.schedMin, slot: alert.slot, kind: alert.kind,
            params: alert.params?.mapValues(\.any)
        ))
        update(alert.id) { $0.pushRegistered = diag.ok }
    }

    /// A local (push-less) notification once per trip; true if it spoke now.
    @discardableResult
    func notifyLocallyOnce(stopId: String, slot: String, tripId: String, title: String, body: String) -> Bool {
        guard let alert = find(stopId: stopId, slot: slot), !alert.pushRegistered,
              !(alert.notifiedTripIds ?? []).contains(tripId) else { return false }
        let center = NotificationCenterStore.shared
        // The main switch and "Ne zavarj" apply to local alerts too.
        guard center.isAuthorized, center.settings.enabled, !center.isWithinDnd() else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["stopId": stopId]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: String("mvk-\(slot)-\(tripId)".prefix(60)), content: content, trigger: nil))
        update(alert.id) { $0.notifiedTripIds = Array(($0.notifiedTripIds ?? []).suffix(20)) + [tripId] }
        return true
    }

    /// Expired one-off (trip-bound) alerts go; the server drops them too.
    func prune(maxAge: TimeInterval = 4 * 3600) {
        let now = Date().timeIntervalSince1970 * 1000
        let keep = alerts.filter { $0.schedMin != nil || $0.kind == "traffic" || now - $0.createdAt < maxAge * 1000 }
        if keep.count != alerts.count { write(keep) }
    }
}

// MARK: - Local evaluation

/// The fields of a departure that the alert texts need (the shared
/// `ArrivalItem` carries only the basics).
private struct AlertArrival: Decodable {
    let route: String
    let headsign: String
    let time: String
    let etaMin: Int
    let delaySec: Int?
    let tripId: String
    let mode: String?
    let trainNo: String?
    let trainName: String?
    let cancelled: Bool?
    let schedUnix: Double?
    let forecastDelaySec: Double?
    let forecastUpperSec: Double?
    let measuredDelaySec: Double?
    let trafficAhead: Traffic?
    let vehicle: Vehicle?

    struct Traffic: Decodable { let excessS: Double; let fromName: String; let toName: String }
    struct Vehicle: Decodable { let id: String }
}

private struct AlertBoard: Decodable {
    let arrivals: [AlertArrival]
}

/// What the server's push engine does for each alert kind, run on the phone
/// for alerts the server cannot push (no APNs key, registration failed).
/// Transfers need the server's transfer outlook and are push-only.
@MainActor
enum LocalAlertEvaluator {
    private static let walkMps = 1.3
    private static let runMps = 2.7
    private static let safetyS = 30.0
    private static let goWindowS = 90.0
    private static let trafficAlertS = 150.0
    private static let trafficHorizonMin = 30
    private static let recurringWindowMin = 4

    static func run() async {
        AlertsStore.shared.prune()
        let pending = AlertsStore.shared.alerts.filter { !$0.pushRegistered && $0.kind != "transfer" }
        let stopIds = Set(pending.map(\.stopId))
        for stopId in stopIds {
            guard let board = await fetch(stopId) else { continue }
            for alert in pending where alert.stopId == stopId {
                if alert.kind == "leave" { evaluateLeave(alert, board.arrivals) }
                if alert.kind == "traffic" { evaluateTraffic(alert, board.arrivals) }
            }
        }
    }

    private static func fetch(_ stopId: String) async -> AlertBoard? {
        let local = LocalStore.shared
        let items = [
            URLQueryItem(name: "stop", value: stopId),
            URLQueryItem(name: "limit", value: "40"),
            URLQueryItem(name: "modes", value: local.modesParam),
            URLQueryItem(name: "merge", value: local.stopMerge.rawValue),
        ]
        return try? await APIClient.shared.request(path: "/live/arrivals", queryItems: items)
    }

    private static func label(_ a: AlertArrival) -> String {
        if a.mode == "rail" {
            return "\(HungarianText.withSuffix(a.trainNo ?? a.route)) vonat\(a.trainName.map { " (\($0))" } ?? "")"
        }
        let vehicle = a.vehicle.map { " (\($0.id.replacingOccurrences(of: "hkir:hkir_", with: "")))" } ?? ""
        return "\(HungarianText.withSuffix(a.route)) \(a.mode == "tram" ? "villamos" : "busz")\(vehicle)"
    }

    private static func minText(_ seconds: Double) -> String { "\(max(1, Int((seconds / 60).rounded()))) perc" }

    private static func delaySuffix(_ delay: Double?) -> String {
        guard let delay, abs(delay) >= 60 else { return "" }
        let minutes = Int((abs(delay) / 60).rounded())
        return delay > 0 ? " (\(minutes) perc késés)" : " (\(minutes) perccel korábban)"
    }

    private static func minuteOfDay() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: Date())
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func relevant(_ alert: AlertWatch, _ arrivals: [AlertArrival]) -> [AlertArrival] {
        let routes = alert.routeShorts.flatMap { $0.isEmpty ? nil : $0 }
        let nowMin = minuteOfDay()
        return arrivals.filter { a in
            if let sched = alert.schedMin {
                if let routes, !routes.contains(a.route) { return false }
                let delayMin = Int((Double(a.delaySec ?? 0) / 60).rounded())
                let aSched = ((nowMin + a.etaMin - delayMin) % 1440 + 1440) % 1440
                let d = abs(aSched - sched)
                return min(d, 1440 - d) <= recurringWindowMin
            }
            if let trip = alert.tripId { return a.tripId == trip }
            return routes.map { $0.contains(a.route) } ?? true
        }
    }

    private static func evaluateLeave(_ alert: AlertWatch, _ arrivals: [AlertArrival]) {
        let walkS = min(3600, max(0, alert.params?["walkS"]?.number ?? 0))
        let now = Date().timeIntervalSince1970
        for a in relevant(alert, arrivals) where a.cancelled != true {
            let at: Double
            var upper: Double?
            if let sched = a.schedUnix, let forecast = a.forecastDelaySec {
                at = sched + forecast
                upper = a.forecastUpperSec.map { sched + $0 }
            } else {
                at = now + Double(a.etaMin) * 60
            }
            guard at - now <= 3600 else { continue }
            let spread = upper.map { min(120, max(30, max(0, $0 - at) * 0.35)) } ?? 45
            let leaveAt = at - spread - walkS - safetyS
            let runS = walkS * walkMps / runMps
            if leaveAt - now > goWindowS { continue }
            let eta = minText(at - now)
            if now + walkS <= at {
                AlertsStore.shared.notifyLocallyOnce(stopId: alert.stopId, slot: alert.slot, tripId: a.tripId,
                    title: "Indulj most: \(label(a)) \(eta) múlva",
                    body: "\(alert.stopName) \(minText(walkS)) séta\(delaySuffix(a.measuredDelaySec ?? a.delaySec.map(Double.init))).")
            } else if now + runS <= at {
                AlertsStore.shared.notifyLocallyOnce(stopId: alert.stopId, slot: alert.slot, tripId: a.tripId,
                    title: "Siess! \(label(a)) \(eta) múlva",
                    body: "\(alert.stopName) \(minText(walkS)) séta, csak futva éred el\(delaySuffix(a.measuredDelaySec ?? a.delaySec.map(Double.init))).")
            }
        }
    }

    private static func evaluateTraffic(_ alert: AlertWatch, _ arrivals: [AlertArrival]) {
        let routes = alert.routeShorts.flatMap { $0.isEmpty ? nil : $0 }
        for a in arrivals {
            guard let traffic = a.trafficAhead, traffic.excessS >= trafficAlertS, a.cancelled != true, a.etaMin <= trafficHorizonMin else { continue }
            if let routes, !routes.contains(a.route) { continue }
            AlertsStore.shared.notifyLocallyOnce(stopId: alert.stopId, slot: alert.slot, tripId: a.tripId,
                title: "Dugó: \(label(a)) kb. +\(minText(traffic.excessS))",
                body: "\(traffic.fromName) → \(traffic.toName) között beállt a forgalom kb. \(a.etaMin) perc múlva ér a \(alert.stopName) megállóba.")
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
