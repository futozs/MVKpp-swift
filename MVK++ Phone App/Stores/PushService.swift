//
//  PushService.swift
//  MVK++ Phone App
//

import Combine
import Foundation
import UIKit
import UserNotifications

/// Server-side watches delivered over APNs (web `lib/push.ts`).
///
/// The iPhone is a push subscription whose endpoint is
/// `apns:<sandbox|production>:<device token>`; the same `/push/*` routes the
/// web uses take it. When the server has no APNs key configured, or a
/// registration fails, the app falls back to local notifications.
@MainActor
final class PushService: ObservableObject {
    static let shared = PushService()

    @Published private(set) var deviceToken: String?
    /// The server can send APNs (`GET /push/apns`); nil until asked.
    @Published private(set) var serverConfigured: Bool?

    struct Diagnostic {
        let ok: Bool
        var reason: String?
    }

    private static let tokenKey = "mvk_push_token"
    private var watchesSubscription: AnyCancellable?
    private var lastSynced: [String: NotifyWatch] = [:]

    private init() {
        deviceToken = UserDefaults.standard.string(forKey: Self.tokenKey)
    }

    #if DEBUG
    private static let environment = "sandbox"
    #else
    private static let environment = "production"
    #endif

    var endpoint: String? { deviceToken.map { "apns:\(Self.environment):\($0)" } }

    // MARK: - Registration

    /// Once at launch: ask for a device token when notifications are allowed,
    /// and mirror stop watches set anywhere in the app onto the server.
    func start() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await refreshConfigured()
        }
        lastSynced = NotificationCenterStore.shared.watches
        watchesSubscription = NotificationCenterStore.shared.$watches
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] watches in self?.mirror(watches) }
    }

    func didRegister(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        guard hex != deviceToken else { return }
        deviceToken = hex
        UserDefaults.standard.set(hex, forKey: Self.tokenKey)
        // A new token means a new subscription: every watch goes up again.
        Task { await reRegisterAll() }
    }

    func refreshConfigured() async {
        struct Reply: Decodable { let configured: Bool }
        let reply: Reply? = try? await APIClient.shared.request(path: "/push/apns")
        serverConfigured = reply?.configured ?? false
    }

    /// After permission is granted the device token can be requested.
    func permissionGranted() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Watches

    private func params(_ extra: [String: Any]? = nil) -> [String: Any] {
        var out: [String: Any] = ["modes": LocalStore.shared.modesParam, "merge": LocalStore.shared.stopMerge.rawValue]
        for (key, value) in extra ?? [:] { out[key] = value }
        return out
    }

    struct WatchConfig {
        var stopId: String
        var stopName: String
        var thresholdMin: Int
        var routeShorts: [String]?
        var tripId: String?
        var isDeparture: Bool?
        var schedMin: Int?
        var slot: String?
        var kind: String?
        var params: [String: Any]?
    }

    func registerWatch(_ config: WatchConfig) async -> Diagnostic {
        if serverConfigured == nil { await refreshConfigured() }
        guard serverConfigured == true else {
            return Diagnostic(ok: false, reason: "A szerveren nincs beállítva az iPhone-os push (APNs), nyitott appnál és háttérfrissítéssel szólok.")
        }
        guard let endpoint else {
            return Diagnostic(ok: false, reason: "Az iPhone még nem adott push-azonosítót. Próbáld újra pár másodperc múlva.")
        }
        var body: [String: Any] = [
            "subscription": ["endpoint": endpoint],
            "stopId": config.stopId,
            "stopName": config.stopName,
            "thresholdMin": config.thresholdMin,
            "params": params(config.params),
        ]
        if let value = config.routeShorts, !value.isEmpty { body["routeShorts"] = value }
        if let value = config.tripId { body["tripId"] = value }
        if let value = config.isDeparture { body["isDeparture"] = value }
        if let value = config.schedMin { body["schedMin"] = value }
        if let value = config.slot { body["slot"] = value }
        if let value = config.kind { body["kind"] = value }
        do {
            let status = try await send("POST", "/push/watch", body)
            guard (200..<300).contains(status) else {
                return Diagnostic(ok: false, reason: "A szerver elutasította a mentést (\(status)).")
            }
            // DND and the main switch can only be stored on an existing
            // subscription: carry them over now the subscription exists.
            let settings = NotificationCenterStore.shared.settings
            _ = await setDnd(enabled: settings.dndEnabled, startMin: settings.dndStartMin, endMin: settings.dndEndMin)
            if !settings.enabled { _ = await setEnabled(false) }
            return Diagnostic(ok: true)
        } catch {
            return Diagnostic(ok: false, reason: "Nem sikerült elérni a szervert: \(error.localizedDescription)")
        }
    }

    func unregisterWatch(stopId: String, slot: String = "default") async {
        guard let endpoint else { return }
        _ = try? await send("DELETE", "/push/watch", ["endpoint": endpoint, "stopId": stopId, "slot": slot])
    }

    func setDnd(enabled: Bool, startMin: Int, endMin: Int) async -> Diagnostic {
        guard let endpoint else { return Diagnostic(ok: false, reason: "Nincs aktív push-feliratkozás.") }
        do {
            let status = try await send("POST", "/push/dnd", [
                "subscription": ["endpoint": endpoint], "dndEnabled": enabled, "dndStartMin": startMin, "dndEndMin": endMin,
            ])
            return (200..<300).contains(status) ? Diagnostic(ok: true) : Diagnostic(ok: false, reason: "A szerver elutasította (\(status)).")
        } catch {
            return Diagnostic(ok: false, reason: error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool) async -> Diagnostic {
        guard let endpoint else { return Diagnostic(ok: false, reason: "Nincs aktív push-feliratkozás.") }
        do {
            let status = try await send("POST", "/push/enabled", ["subscription": ["endpoint": endpoint], "enabled": enabled])
            return (200..<300).contains(status) ? Diagnostic(ok: true) : Diagnostic(ok: false, reason: "A szerver elutasította (\(status)).")
        } catch {
            return Diagnostic(ok: false, reason: error.localizedDescription)
        }
    }

    // MARK: - Live Activities

    /// Hands an ActivityKit push token to the server, which then pushes the
    /// followed trip's progress (`content-state`) until the trip ends.
    /// `stopId` is where the rider gets off, `fromStopId` where they got on:
    /// the server counts progress and stops left between the two.
    func registerLiveActivity(token: Data, tripId: String, vehicleId: String?, stopId: String?, fromStopId: String? = nil) async -> Bool {
        var body: [String: Any] = [
            "token": token.map { String(format: "%02x", $0) }.joined(),
            "env": Self.environment,
            "tripId": tripId,
            "deviceId": DeviceIdentity.id,
        ]
        if let vehicleId { body["vehicleId"] = vehicleId }
        if let stopId { body["stopId"] = stopId }
        if let fromStopId { body["fromStopId"] = fromStopId }
        let status = (try? await send("POST", "/push/live-activity", body)) ?? 0
        return (200..<300).contains(status)
    }

    func endLiveActivity(token: Data) async {
        _ = try? await send("DELETE", "/push/live-activity", ["token": token.map { String(format: "%02x", $0) }.joined()])
    }

    struct Delivery: Decodable, Identifiable {
        let id: Int
        let kind: String
        let status: String
        let attempts: Int
        let last_error: String?
        let title: String?
        let body: String?
        let created_at: String
        let sent_at: String?
        let stop_name: String
    }

    /// The device's latest pushes: what went out, what did not, and why.
    func deliveries() async -> [Delivery] {
        guard let endpoint else { return [] }
        struct Reply: Decodable { let deliveries: [Delivery] }
        guard let url = try? APIClient.shared.url(path: "/v3/push/state"),
              let body = try? JSONSerialization.data(withJSONObject: ["endpoint": endpoint]) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        guard let (data, response) = try? await APIClient.shared.session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let reply = try? JSONDecoder().decode(Reply.self, from: data)
        else { return [] }
        return reply.deliveries
    }

    private func send(_ method: String, _ path: String, _ body: [String: Any]) async throws -> Int {
        var request = URLRequest(url: try APIClient.shared.url(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await APIClient.shared.session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    // MARK: - Mirroring the stop watches

    private func config(for watch: NotifyWatch) -> WatchConfig {
        var extra: [String: Any] = [:]
        if let date = watch.date { extra["date"] = date }
        return WatchConfig(
            stopId: watch.stopId, stopName: watch.stopName, thresholdMin: watch.thresholdMin,
            routeShorts: watch.routeShorts, tripId: watch.tripId, isDeparture: watch.isDeparture,
            schedMin: watch.schedMin, params: extra
        )
    }

    /// A notify sheet's save: registers the watch on the server at once and
    /// reports the outcome, which the sheet shows (web `registerPushWatch`).
    /// Marked as synced first, so the mirror below does not send it again.
    func register(_ watch: NotifyWatch) async -> Diagnostic {
        lastSynced[watch.stopId] = watch
        let result = await registerWatch(config(for: watch))
        NotificationCenterStore.shared.setPushRegistered(stopId: watch.stopId, result.ok)
        lastSynced[watch.stopId] = NotificationCenterStore.shared.watches[watch.stopId]
        return result
    }

    /// Watches are set by the stop and trip sheets; whatever changed is sent
    /// to (or removed from) the server.
    private func mirror(_ watches: [String: NotifyWatch]) {
        let previous = lastSynced
        lastSynced = watches
        for (stopId, _) in previous where watches[stopId] == nil {
            Task { await unregisterWatch(stopId: stopId) }
        }
        for (stopId, watch) in watches where !Self.sameTarget(previous[stopId], watch) {
            Task {
                let result = await registerWatch(config(for: watch))
                NotificationCenterStore.shared.setPushRegistered(stopId: stopId, result.ok)
                lastSynced[stopId] = NotificationCenterStore.shared.watches[stopId]
            }
        }
    }

    private static func sameTarget(_ a: NotifyWatch?, _ b: NotifyWatch) -> Bool {
        guard let a else { return false }
        return a.thresholdMin == b.thresholdMin && a.routeShorts == b.routeShorts && a.tripId == b.tripId
            && a.schedMin == b.schedMin && a.isDeparture == b.isDeparture && a.date == b.date
    }

    private func reRegisterAll() async {
        for (stopId, watch) in NotificationCenterStore.shared.watches {
            let result = await registerWatch(config(for: watch))
            NotificationCenterStore.shared.setPushRegistered(stopId: stopId, result.ok)
        }
        for alert in AlertsStore.shared.alerts {
            await AlertsStore.shared.reRegister(alert)
        }
        lastSynced = NotificationCenterStore.shared.watches
    }
}
