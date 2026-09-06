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
}

struct NotificationSettings: Codable, Equatable {
    var enabled: Bool = true
    var dndEnabled: Bool = false
    var dndStartMin: Int = 22 * 60
    var dndEndMin: Int = 7 * 60

    static let `default` = NotificationSettings()
}

/// Without a delegate, iOS delivers a notification *silently* while the app is
/// in the foreground — which is exactly when someone tests an arrival alarm,
/// and exactly why they conclude it is broken.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
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
        }
    }
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let presenter = NotificationPresenter()

    private init() {
        watches = Self.load([String: NotifyWatch].self, key: Self.watchesKey) ?? [:]
        settings = Self.load(NotificationSettings.self, key: Self.settingsKey) ?? .default
    }

    /// Call once at launch. Registers the foreground presenter and reads the
    /// real authorisation state — without this, `authorization` stays
    /// `.notDetermined` after a relaunch and every alarm is skipped.
    func configure() async {
        UNUserNotificationCenter.current().delegate = presenter
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

    func setWatch(_ watch: NotifyWatch) {
        watches[watch.stopId] = watch
        persistWatches()
    }

    func removeWatch(stopId: String) {
        watches.removeValue(forKey: stopId)
        persistWatches()
    }

    // MARK: - Firing

    /// Called on every arrivals refresh.
    ///
    /// Rather than waiting for the ETA to fall inside the threshold and firing
    /// then — which only works while the app happens to be polling — the
    /// notification is *scheduled* for the moment it comes due. iOS delivers a
    /// scheduled local notification even if the app is closed by then, so the
    /// rider gets it whether or not MVK++ is still on screen.
    func scheduleAlarm(stopId: String, stopName: String, arrivals: [ArrivalItem]) {
        guard settings.enabled, isAuthorized, let watch = watches[stopId] else { return }

        let center = UNUserNotificationCenter.current()
        let identifier = Self.identifier(stopId: stopId)

        guard let next = arrivals.first(where: { isTargeted($0, watch: watch) }) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        // How long until the bus is `thresholdMin` away.
        let leadSeconds = Double(next.etaMin - watch.thresholdMin) * 60

        if leadSeconds <= 0 {
            fireNow(next, watch: watch, stopId: stopId, stopName: stopName, identifier: identifier)
            return
        }

        // Do-not-disturb is judged at the moment it would arrive, not now.
        guard !isWithinDnd(now: Date().addingTimeInterval(leadSeconds)) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content(for: [next], watch: watch, stopId: stopId, stopName: stopName),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: leadSeconds, repeats: false)
        )
        // Same identifier every time, so each refresh simply corrects the
        // pending alarm as the prediction moves.
        center.add(request)
    }

    private func fireNow(
        _ arrival: ArrivalItem,
        watch: NotifyWatch,
        stopId: String,
        stopName: String,
        identifier: String
    ) {
        guard !isWithinDnd() else { return }
        // One announcement per run — the bus stays inside the threshold for
        // several polls on its way in.
        guard !(watch.lastNotifiedTripIds ?? []).contains(arrival.tripId) else { return }

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: identifier,
                content: content(for: [arrival], watch: watch, stopId: stopId, stopName: stopName),
                trigger: nil
            )
        )

        var updated = watch
        updated.lastNotifiedTripIds = [arrival.tripId]
        watches[stopId] = updated
        persistWatches()
    }

    func cancelAlarm(stopId: String) {
        let identifier = Self.identifier(stopId: stopId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private static func identifier(stopId: String) -> String { "mvk-stop-\(stopId)" }

    private func content(
        for arrivals: [ArrivalItem],
        watch: NotifyWatch,
        stopId: String,
        stopName: String
    ) -> UNMutableNotificationContent {
        let minEta = max(0, arrivals.map(\.etaMin).min() ?? 0)

        let label: (ArrivalItem) -> String = { arrival in
            let route = HungarianText.withSuffix(arrival.route)
            if let vehicleId = arrival.vehicle?.id { return "\(route) busz (\(vehicleId))" }
            return "\(route) busz"
        }

        let content = UNMutableNotificationContent()
        content.title = arrivals.map(label).joined(separator: ", ")

        let delayNote = arrivals.count == 1 ? Self.delaySuffix(arrivals[0].delaySec) : ""
        let isPinnedRun = watch.tripId != nil || watch.schedMin != nil
        content.body = isPinnedRun
            ? "kb. \(minEta) percen belül \(watch.isDeparture == true ? "indul" : "ér ide")\(delayNote) — \(stopName) (\(stopId))"
            : "\(stopName) (\(stopId)) — kb. \(minEta) percen belül\(delayNote)"
        content.sound = .default
        content.threadIdentifier = Self.identifier(stopId: stopId)
        return content
    }

    /// Whether this departure is one the watch cares about — route, pinned
    /// trip or pinned scheduled minute. The threshold is applied separately,
    /// because scheduling needs the next match regardless of how far off it is.
    private func isTargeted(_ arrival: ArrivalItem, watch: NotifyWatch) -> Bool {
        guard arrival.etaMin >= 0 else { return false }
        return matches(arrival, watch: watch)
    }

    private func matches(_ arrival: ArrivalItem, watch: NotifyWatch) -> Bool {
        if let schedMin = watch.schedMin {
            if let routes = watch.routeShorts, !routes.isEmpty, !routes.contains(arrival.route) {
                return false
            }
            // Work back from the live ETA to the scheduled minute, so a late
            // bus still matches the run the rider actually pinned.
            let delayMin = Int((Double(arrival.delaySec ?? 0) / 60).rounded())
            let nowMin = Self.minutesSinceMidnight()
            let arrivalSchedMin = ((nowMin + arrival.etaMin - delayMin) % 1440 + 1440) % 1440
            if Self.minuteDistance(arrivalSchedMin, schedMin) > Self.recurringWindowMin { return false }
        } else if let tripId = watch.tripId {
            if arrival.tripId != tripId { return false }
        } else if let routes = watch.routeShorts, !routes.isEmpty, !routes.contains(arrival.route) {
            return false
        }

        return true
    }

    private func post(fresh: [ArrivalItem], watch: NotifyWatch, stopId: String, stopName: String) {
        let minEta = max(0, fresh.map(\.etaMin).min() ?? 0)

        let label: (ArrivalItem) -> String = { arrival in
            let route = HungarianText.withSuffix(arrival.route)
            if let vehicleId = arrival.vehicle?.id { return "\(route) busz (\(vehicleId))" }
            return "\(route) busz"
        }

        let content = UNMutableNotificationContent()
        content.title = fresh.map(label).joined(separator: ", ")

        let delayNote = fresh.count == 1 ? Self.delaySuffix(fresh[0].delaySec) : ""
        let isPinnedRun = watch.tripId != nil || watch.schedMin != nil
        content.body = isPinnedRun
            ? "kb. \(minEta) percen belül \(watch.isDeparture == true ? "indul" : "ér ide")\(delayNote) — \(stopName) (\(stopId))"
            : "\(stopName) (\(stopId)) — kb. \(minEta) percen belül\(delayNote)"
        content.sound = .default
        // One live notification per stop: a replacement, not a pile.
        content.threadIdentifier = "mvk-stop-\(stopId)"

        let request = UNNotificationRequest(
            identifier: "mvk-stop-\(stopId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Do not disturb

    func isWithinDnd(now: Date = Date()) -> Bool {
        guard settings.dndEnabled, settings.dndStartMin != settings.dndEndMin else { return false }
        let nowMin = Self.minutesSinceMidnight(now)
        // A window that wraps past midnight (22:00–07:00) inverts the test.
        if settings.dndStartMin < settings.dndEndMin {
            return nowMin >= settings.dndStartMin && nowMin < settings.dndEndMin
        }
        return nowMin >= settings.dndStartMin || nowMin < settings.dndEndMin
    }

    // MARK: - Helpers

    private static func minutesSinceMidnight(_ date: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Distance between two minutes of the day, the short way round the clock.
    private static func minuteDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b)
        return min(d, 1440 - d)
    }

    private static func delaySuffix(_ delaySec: Int?) -> String {
        guard let delaySec, abs(delaySec) >= delayMentionThresholdSec else { return "" }
        let min = Int((Double(abs(delaySec)) / 60).rounded())
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
