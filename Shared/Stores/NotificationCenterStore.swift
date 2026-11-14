//
//  NotificationCenterStore.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Combine
import Foundation
import UserNotifications

/// A standing request to be told when something is about to reach a stop.
///
/// Three shapes of watch, in narrowing order: any route at the stop, a chosen
/// set of routes, or one specific run — pinned either by trip ID or by its
/// scheduled minute of the day, so a daily commute keeps working tomorrow when
/// the trip ID has changed.
struct NotifyWatch: Codable, Hashable {
    var stopId: String
    var stopName: String
    /// Alert once the vehicle is within this many minutes.
    var thresholdMin: Int
    var routeShorts: [String]?
    var tripId: String?
    /// The pinned run departs from here rather than passing through.
    var isDeparture: Bool?
    /// Minutes past midnight of the pinned run's scheduled time.
    var schedMin: Int?
    /// Trips already announced, so one bus is not reported twice as it closes.
    var lastNotifiedTripIds: [String]?
    /// A one-off trip watch: the service day it is for (the same trip ID is
    /// another run on another day).
    var date: String?
    /// The server delivers this one by push (APNs), so the device stays quiet.
    var pushRegistered: Bool?
    /// The run the pending local alarm is set for, and when it goes off:
    /// once it has fired, the same bus is not announced again.
    var scheduledTripId: String?
    var scheduledFireAt: TimeInterval?
    /// When the watch was first set, unix seconds. The list keeps this order,
    /// as the web keeps its insertion order; editing a watch keeps its place.
    var createdAt: TimeInterval?
}

extension Notification.Name {
    /// The main switch or the quiet hours changed and pending alarms were
    /// withdrawn: whoever plans alarms ahead plans them again.
    static let mvkNotificationSettingsChanged = Notification.Name("mvk-notification-settings-changed")
}

struct NotificationSettings: Codable, Equatable {
    var enabled: Bool = true
    var dndEnabled: Bool = false
    var dndStartMin: Int = 22 * 60
    var dndEndMin: Int = 7 * 60

    static let `default` = NotificationSettings()
}

@MainActor
final class NotificationCenterStore: ObservableObject {

    static let shared = NotificationCenterStore()

    static let defaultThresholdMin = 5
    /// Below a minute the deviation is not worth mentioning in the message.
    private static let delayMentionThresholdSec = 60
    /// How far a live departure may drift from a pinned scheduled minute and
    /// still count as the same run.
    private static let recurringWindowMin = 4

    private static let watchesKey = "mvk_notify_watches"
    private static let settingsKey = "mvk_notify_settings"

    @Published private(set) var watches: [String: NotifyWatch] = [:]
    @Published var settings: NotificationSettings = .default {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
            withdrawPendingAlarms()
        }
    }
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private init() {
        watches = Self.load([String: NotifyWatch].self, key: Self.watchesKey) ?? [:]
        settings = Self.load(NotificationSettings.self, key: Self.settingsKey) ?? .default
    }

    /// Call once at launch. Reads the real authorisation state — without
    /// this, `authorization` stays `.notDetermined` after a relaunch and every
    /// alarm is skipped.
    func configure() async {
        await refreshAuthorization()
    }

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional
    }

    /// Posts a notification five seconds out, so permission and delivery can
    /// be confirmed without waiting for a bus.
    func sendTestNotification() async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "MVK++ teszt"
        content.body = "Így fog kinézni egy megállóértesítés."
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "mvk-test",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            )
        )
    }

    // MARK: - Permission

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            return granted
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    // MARK: - Watches

    func watch(stopId: String) -> NotifyWatch? { watches[stopId] }

    func hasWatch(stopId: String) -> Bool { watches[stopId] != nil }

    /// The watches in the order they were set (web `getAllWatches`).
    var orderedWatches: [NotifyWatch] {
        watches.values.sorted { ($0.createdAt ?? 0, $0.stopId) < ($1.createdAt ?? 0, $1.stopId) }
    }

    func setWatch(_ watch: NotifyWatch) {
        var next = watch
        next.createdAt = watches[watch.stopId]?.createdAt ?? watch.createdAt ?? Date().timeIntervalSince1970
        watches[watch.stopId] = next
        persistWatches()
    }

    func setPushRegistered(stopId: String, _ registered: Bool) {
        guard var watch = watches[stopId], watch.pushRegistered != registered else { return }
        watch.pushRegistered = registered
        watches[stopId] = watch
        persistWatches()
    }

    func removeWatch(stopId: String) {
        watches.removeValue(forKey: stopId)
        persistWatches()
    }

    // MARK: - Firing

    /// Called on every arrivals refresh (web `checkAndNotify`).
    ///
    /// A bus already inside the threshold is announced at once. The next one
    /// further out is also *scheduled* for the moment it comes due, because iOS
    /// delivers a scheduled local notification even if the app is closed by
    /// then. The scheduled trip is remembered with its fire time, so the
    /// refresh after it fired does not announce the same bus a second time.
    func scheduleAlarm(stopId: String, stopName: String, arrivals: [ArrivalItem]) {
        guard let watch = watches[stopId] else { return }

        let center = UNUserNotificationCenter.current()
        let identifier = Self.identifier(stopId: stopId)

        guard settings.enabled, isAuthorized, watch.pushRegistered != true else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        // A one-day trip watch expires after its day and is silent before it.
        if watch.tripId != nil, let date = watch.date {
            let today = ServiceDay.isoToday()
            if date < today {
                removeWatch(stopId: stopId)
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                return
            }
            if date != today { return }
        }

        let now = Date()
        let nowUnix = now.timeIntervalSince1970
        // A cancelled run never arrives; the server's push skips it too.
        let targeted = arrivals.filter { !$0.isCancelled && $0.etaMin >= 0 && matches($0, watch: watch) }
        var updated = watch

        var alreadyFired: Set<String> = []
        if let scheduled = watch.scheduledTripId, let fireAt = watch.scheduledFireAt, fireAt <= nowUnix {
            if targeted.contains(where: { $0.tripId == scheduled }) {
                alreadyFired.insert(scheduled)
            } else {
                updated.scheduledTripId = nil
                updated.scheduledFireAt = nil
            }
        }

        let inside = targeted.filter { $0.etaMin <= watch.thresholdMin }
        if !isWithinDnd(now: now) {
            let announced = Set(watch.lastNotifiedTripIds ?? []).union(alreadyFired)
            let fresh = inside.filter { !announced.contains($0.tripId) }
            if !fresh.isEmpty {
                if let scheduled = updated.scheduledTripId, fresh.contains(where: { $0.tripId == scheduled }) {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    updated.scheduledTripId = nil
                    updated.scheduledFireAt = nil
                }
                center.add(UNNotificationRequest(
                    identifier: "\(identifier)-now",
                    content: content(for: fresh, watch: watch, stopId: stopId, stopName: stopName),
                    trigger: nil
                ))
            }
            // Trip ids repeat every day: once a bus is gone it is let go, or
            // tomorrow's run with the same id would stay silent.
            updated.lastNotifiedTripIds = inside.isEmpty ? nil : inside.map(\.tripId)
        }

        let handled = Set(updated.lastNotifiedTripIds ?? []).union(alreadyFired)
        if let next = targeted.first(where: { $0.etaMin > watch.thresholdMin && !handled.contains($0.tripId) }) {
            let fireDate = now.addingTimeInterval(Double(next.etaMin - watch.thresholdMin) * 60)
            // Do-not-disturb is judged at the moment it would arrive, not now.
            if isWithinDnd(now: fireDate) {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                updated.scheduledTripId = nil
                updated.scheduledFireAt = nil
            } else {
                // Same identifier every time, so each refresh simply corrects
                // the pending alarm as the prediction moves.
                center.add(UNNotificationRequest(
                    identifier: identifier,
                    // It goes off when the bus is `thresholdMin` away.
                    content: content(for: [next], watch: watch, stopId: stopId, stopName: stopName, etaMin: watch.thresholdMin),
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireDate.timeIntervalSince(now), repeats: false)
                ))
                updated.scheduledTripId = next.tripId
                updated.scheduledFireAt = fireDate.timeIntervalSince1970
            }
        } else if let fireAt = updated.scheduledFireAt, fireAt > nowUnix {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            updated.scheduledTripId = nil
            updated.scheduledFireAt = nil
        }

        if updated != watch {
            watches[stopId] = updated
            persistWatches()
        }
    }

    func cancelAlarm(stopId: String) {
        let identifier = Self.identifier(stopId: stopId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private static func identifier(stopId: String) -> String { "mvk-stop-\(stopId)" }

    /// The web's wording: the train number on a train, „villamos” on a tram,
    /// a bus with its fleet number; a regional stop by name only (its id says
    /// nothing to a rider).
    private func content(
        for arrivals: [ArrivalItem],
        watch: NotifyWatch,
        stopId: String,
        stopName: String,
        etaMin: Int? = nil
    ) -> UNMutableNotificationContent {
        let minEta = max(0, etaMin ?? arrivals.map(\.etaMin).min() ?? 0)

        let label: (ArrivalItem) -> String = { arrival in
            if arrival.mode == .rail {
                return "\(arrival.route)\(arrival.trainNo.map { " \($0)" } ?? "") vonat"
            }
            let noun = arrival.mode == .tram ? "villamos" : "busz"
            let route = HungarianText.withSuffix(arrival.route)
            if let vehicleId = arrival.vehicle?.id { return "\(route) \(noun) (\(TransitIds.displayVehicleId(vehicleId)))" }
            return "\(route) \(noun)"
        }

        let content = UNMutableNotificationContent()
        content.title = arrivals.map(label).joined(separator: ", ")

        let delayNote = arrivals.count == 1 ? Self.delaySuffix(arrivals[0].delaySec) : ""
        let isPinnedRun = watch.tripId != nil || watch.schedMin != nil
        let place = TransitIds.isRegional(stopId) ? stopName : "\(stopName) (\(stopId))"
        content.body = isPinnedRun
            ? "kb. \(minEta) percen belül \(watch.isDeparture == true ? "indul" : "ér ide")\(delayNote), \(place)"
            : "\(place): kb. \(minEta) percen belül\(delayNote)"
        content.sound = .default
        content.threadIdentifier = Self.identifier(stopId: stopId)
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["stopId": stopId]
        return content
    }

    private func matches(_ arrival: ArrivalItem, watch: NotifyWatch) -> Bool {
        if let schedMin = watch.schedMin {
            if let routes = watch.routeShorts, !routes.isEmpty, !routes.contains(arrival.route) {
                return false
            }
            // Work back from the live ETA to the scheduled minute, so a late
            // bus still matches the run the rider actually pinned.
            let delayMin = Int((Double(arrival.delaySec ?? 0) / 60 + 0.5).rounded(.down))
            let nowMin = Self.budapestMinute()
            let arrivalSchedMin = ((nowMin + arrival.etaMin - delayMin) % 1440 + 1440) % 1440
            if Self.minuteDistance(arrivalSchedMin, schedMin) > Self.recurringWindowMin { return false }
        } else if let tripId = watch.tripId {
            if arrival.tripId != tripId { return false }
        } else if let routes = watch.routeShorts, !routes.isEmpty, !routes.contains(arrival.route) {
            return false
        }

        return true
    }

    /// The main switch or the quiet hours changed: alarms already handed to
    /// iOS would still go off, so every pending one is withdrawn. Stop alarms
    /// come back with the next arrivals refresh; the special alerts re-plan
    /// on `mvkNotificationSettingsChanged`.
    private func withdrawPendingAlarms() {
        for (stopId, watch) in watches where watch.scheduledTripId != nil {
            var updated = watch
            updated.scheduledTripId = nil
            updated.scheduledFireAt = nil
            watches[stopId] = updated
        }
        persistWatches()
        Task {
            let center = UNUserNotificationCenter.current()
            let ids = await center.pendingNotificationRequests().map(\.identifier)
                .filter { $0.hasPrefix("mvk-stop-") || $0.hasPrefix("mvk-alert-") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            NotificationCenter.default.post(name: .mvkNotificationSettingsChanged, object: nil)
        }
    }

    // MARK: - Do not disturb

    func isWithinDnd(now: Date = Date()) -> Bool {
        guard settings.dndEnabled, settings.dndStartMin != settings.dndEndMin else { return false }
        let nowMin = Self.budapestMinute(now)
        // A window that wraps past midnight (22:00–07:00) inverts the test.
        if settings.dndStartMin < settings.dndEndMin {
            return nowMin >= settings.dndStartMin && nowMin < settings.dndEndMin
        }
        return nowMin >= settings.dndStartMin || nowMin < settings.dndEndMin
    }

    // MARK: - Helpers

    /// Budapest wall-clock minute of the day, as the server measures it for
    /// pushes, whatever the device's time zone.
    private static func budapestMinute(_ date: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ServiceClock.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Distance between two minutes of the day, the short way round the clock.
    private static func minuteDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b)
        return min(d, 1440 - d)
    }

    private static func delaySuffix(_ delaySec: Int?) -> String {
        guard let delaySec, abs(delaySec) >= delayMentionThresholdSec else { return "" }
        let min = Int((Double(abs(delaySec)) / 60 + 0.5).rounded(.down))
        return delaySec > 0 ? " (\(min) perc késés)" : " (\(min) perccel korábban)"
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persistWatches() {
        guard let data = try? JSONEncoder().encode(watches) else { return }
        UserDefaults.standard.set(data, forKey: Self.watchesKey)
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
}
