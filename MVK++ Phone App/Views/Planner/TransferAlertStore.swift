//
//  TransferAlertStore.swift
//  MVK++ Phone App
//

import Combine
import Foundation
import UserNotifications

/// „Figyeld az átszállást”: the watched transfers, kept under the web's
/// `mvk_alert_watches` key in its `AlertWatch` shape (`slot` `transfer:<trip>`,
/// `kind` `transfer`). Other kinds of alert on the same key are left as they are.
///
/// The server's push channel is web push, which an iOS app cannot receive, so
/// this is the web's no-push path: while the planner keeps the plan fresh the
/// transfer is checked on the device, and a local notification goes out once
/// when its chance drops below the server's threshold.
@MainActor
final class TransferAlertStore: ObservableObject {
    static let shared = TransferAlertStore()

    static let key = "mvk_alert_watches"
    /// Below this chance the transfer counts as in danger (the server's `TRANSFER_ALERT_CHANCE`).
    static let alertChance = 0.4

    struct Alert: Hashable {
        let stopId: String
        let slot: String
        let toTripId: String
    }

    @Published private(set) var alerts: [Alert] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alerts = Self.transferAlerts(in: readAll())
    }

    static func slot(_ check: JourneyTransferCheck) -> String? {
        check.toTripId.map { "transfer:\($0)" }
    }

    func isOn(_ check: JourneyTransferCheck) -> Bool {
        guard let slot = Self.slot(check), let stop = check.boardStopId else { return false }
        return alerts.contains { $0.stopId == stop && $0.slot == slot }
    }

    struct AddResult {
        let ok: Bool
        let reason: String?
    }

    func add(_ check: JourneyTransferCheck) async -> AddResult {
        guard let slot = Self.slot(check), let stopId = check.boardStopId, let toTrip = check.toTripId,
              let fromTrip = check.fromTripId, let alight = check.alightStopId else {
            return AddResult(ok: false, reason: "Nem sikerült bekapcsolni.")
        }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await NotificationCenterStore.shared.refreshAuthorization()
        guard granted else {
            let denied = await center.notificationSettings().authorizationStatus == .denied
            return AddResult(ok: false, reason: denied ? "Az értesítések le vannak tiltva a készüléken." : "Az értesítéshez engedély kell.")
        }
        var params: [String: Any] = [
            "fromTrip": fromTrip,
            "alightStopId": alight,
            "walkS": Int((check.walkS ?? 0).rounded()),
            "boardStopName": check.at,
        ]
        if let fromRoute = check.fromRoute { params["fromRoute"] = fromRoute }
        if let toRoute = check.toRoute { params["toRoute"] = toRoute }
        let entry: [String: Any] = [
            "slot": slot,
            "kind": "transfer",
            "stopId": stopId,
            "stopName": check.at,
            "tripId": toTrip,
            "params": params,
            "pushRegistered": false,
            "createdAt": Int(Date().timeIntervalSince1970 * 1000),
        ]
        let rest = readAll().filter { !Self.matches($0, stopId: stopId, slot: slot) }
        writeAll(rest + [entry])
        return AddResult(ok: true, reason: nil)
    }

    func remove(_ check: JourneyTransferCheck) {
        guard let slot = Self.slot(check), let stopId = check.boardStopId else { return }
        writeAll(readAll().filter { !Self.matches($0, stopId: stopId, slot: slot) })
    }

    /// Without push the rider only hears about it while the app is open.
    static let noPushNote = "Push nélkül csak akkor szólok, ha nyitva van az app."

    // MARK: - Local check

    /// Called with every fresh plan: a watched transfer whose chance has
    /// dropped gets one local notification, with the next option if missed.
    func evaluate(_ plan: JourneyPlanResponse) {
        guard plan.mode == .now, !alerts.isEmpty, NotificationCenterStore.shared.settings.enabled,
              !NotificationCenterStore.shared.isWithinDnd() else { return }
        let now = RealtimeClient.shared.serverNow
        for trip in plan.trips {
            for check in trip.transferChecks where isOn(check) {
                guard let chance = check.chance, chance < Self.alertChance,
                      let toTrip = check.toTripId, let stopId = check.boardStopId,
                      let depart = departUnix(trip: trip, toTrip: toTrip),
                      depart >= now - 60, depart - now <= 3600 else { continue }
                notifyOnce(stopId: stopId, slot: "transfer:\(toTrip)", tripId: toTrip, check: check)
            }
        }
    }

    private func departUnix(trip: JourneyTrip, toTrip: String) -> Double? {
        guard let leg = trip.legs.first(where: { $0.tripId == toTrip }), let sched = leg.schedDep else { return nil }
        return sched + (leg.prediction?.depDelayS ?? 0)
    }

    private func notifyOnce(stopId: String, slot: String, tripId: String, check: JourneyTransferCheck) {
        var all = readAll()
        guard let index = all.firstIndex(where: { Self.matches($0, stopId: stopId, slot: slot) }) else { return }
        let notified = all[index]["notifiedTripIds"] as? [String] ?? []
        guard !notified.contains(tripId) else { return }

        let pct = Int(((check.chance ?? 0) * 100).rounded())
        let fromRoute = check.fromRoute.map { HungarianText.withSuffix($0) + " " } ?? ""
        let toRoute = check.toRoute.map { HungarianText.withSuffix($0) } ?? "csatlakozás"
        let late = check.marginSec < 0 ? "\(PlannerFormat.minutes(-check.marginSec)) késéssel" : "épp csak"
        let fallback = check.fallback.map { " Ha lekésed: \($0.time)." } ?? ""

        let content = UNMutableNotificationContent()
        content.title = "Veszélyben az átszállás (\(pct)% esély)"
        content.body = "A \(fromRoute)busz várhatóan \(late) ér ide a \(toRoute) indulásához  \(check.at).\(fallback)"
        content.sound = .default
        content.threadIdentifier = "mvk-\(stopId)-\(tripId)-transfer"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "mvk-\(stopId)-\(tripId)-transfer", content: content, trigger: nil)
        )

        all[index]["notifiedTripIds"] = Array((notified + [tripId]).suffix(21))
        writeAll(all)
    }

    // MARK: - Storage

    private static func matches(_ entry: [String: Any], stopId: String, slot: String) -> Bool {
        entry["stopId"] as? String == stopId && entry["slot"] as? String == slot
    }

    private static func transferAlerts(in all: [[String: Any]]) -> [Alert] {
        all.compactMap { entry in
            guard entry["kind"] as? String == "transfer",
                  let stopId = entry["stopId"] as? String,
                  let slot = entry["slot"] as? String,
                  let trip = entry["tripId"] as? String else { return nil }
            return Alert(stopId: stopId, slot: slot, toTripId: trip)
        }
    }

    private func readAll() -> [[String: Any]] {
        let raw: Data?
        if let data = defaults.data(forKey: Self.key) {
            raw = data
        } else {
            raw = defaults.string(forKey: Self.key).map { Data($0.utf8) }
        }
        guard let raw, let list = try? JSONSerialization.jsonObject(with: raw) as? [[String: Any]] else { return [] }
        return list
    }

    private func writeAll(_ list: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: list) {
            defaults.set(data, forKey: Self.key)
        }
        alerts = Self.transferAlerts(in: list)
    }
}
