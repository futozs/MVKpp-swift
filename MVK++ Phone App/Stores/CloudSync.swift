//
//  CloudSync.swift
//  MVK++ Phone App
//

import Combine
import Foundation
import UIKit

/// Rebuilds every store from storage — the native `location.reload()`.
/// Remote settings that arrived from another device are taken over this
/// way, exactly like the web reloads the page.
@MainActor
final class AppReloader: ObservableObject {
    static let shared = AppReloader()
    @Published private(set) var generation = 0

    func reload() { generation += 1 }
}

extension Notification.Name {
    /// Keys a sync wrote locally (web `mvk-sync-applied`).
    static let mvkSyncApplied = Notification.Name("mvk-sync-applied")
    /// Sign-out on a shared device: ride history must not carry over to the
    /// next account (web `mvk-rides-reset`).
    static let mvkRidesReset = Notification.Name("mvk-rides-reset")
}

/// Which storage holds each synced key, in the web's `localStorage` string
/// form.
///
/// Every `mvk_*` string in `UserDefaults.standard` syncs as is — that is how
/// `LocalStore` writes. A store that keeps its value in another shape (an
/// App Group array, encoded `Data`) registers a binding that converts to and
/// from the web string, so the same key round-trips between browser and phone.
@MainActor
enum SyncRegistry {
    struct Binding {
        let read: () -> String?
        let write: (String?) -> Void
    }

    /// Device-bound keys (web `DEVICE_ONLY`) plus this engine's own state.
    static let deviceOnly: Set<String> = [
        "mvk_account", "mvk_device_id", "mvk_sync_meta", "mvk_sync_known", "mvk_install_dismissed",
        "mvk_geo_last_fix", "mvk_geo_enabled", "mvk_notify_watches", "mvk_notify_settings",
        "mvk_view_state", "mvk_map_view", "mvk_timetable_view", "mvk_rides", "mvk_ride_active",
        "mvk_ride_deleted", "mvk_heat_route", "mvk_map_panel", "mvk_watch_view", "mvk_alert_watches",
        "mvk_push_token",
    ]
    /// Native-only state the web knows nothing about (offline pack, widget).
    private static let nativePrefixes = ["mvk_offline_", "mvk_widget_", "mvk_stop_cache", "mvk_sync_", "mvk_apns_"]

    private static var bindings: [String: Binding] = defaultBindings()

    static func register(_ key: String, read: @escaping () -> String?, write: @escaping (String?) -> Void) {
        bindings[key] = Binding(read: read, write: write)
    }

    static func syncable(_ key: String) -> Bool {
        key.hasPrefix("mvk_") && !deviceOnly.contains(key) && !nativePrefixes.contains { key.hasPrefix($0) }
    }

    static func currentValue(_ key: String) -> String? {
        if let binding = bindings[key] { return binding.read() }
        return UserDefaults.standard.string(forKey: key)
    }

    static func write(_ key: String, _ value: String?) {
        if let binding = bindings[key] {
            binding.write(value)
        } else if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Every syncable key with its current web-form value.
    static func snapshot() -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where syncable(key) && bindings[key] == nil {
            if let text = value as? String { out[key] = text }
        }
        for key in bindings.keys where syncable(key) {
            if let value = bindings[key]?.read() { out[key] = value }
        }
        return out
    }

    // MARK: - Built-in bindings

    private static var appGroup: UserDefaults { UserDefaults(suiteName: FavoritesStore.appGroupID) ?? .standard }

    private static func jsonString(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes, .fragmentsAllowed]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func jsonObject(_ text: String?) -> Any? {
        guard let text else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
    }

    /// A `Data`-encoded JSON value in `UserDefaults.standard`. Object values
    /// are merged over the last value seen from the cloud, so fields only the
    /// web knows (or only the phone knows) survive a round trip.
    private static func dataBinding(_ key: String, mergeObjects: Bool) -> Binding {
        Binding(
            read: {
                guard let data = UserDefaults.standard.data(forKey: key), let text = String(data: data, encoding: .utf8) else { return nil }
                guard mergeObjects,
                      let local = jsonObject(text) as? [String: Any],
                      let remote = jsonObject(CloudSync.shared.lastRemote(key)) as? [String: Any]
                else { return text }
                return jsonString(remote.merging(local) { _, mine in mine }) ?? text
            },
            write: { value in
                guard let value else {
                    UserDefaults.standard.removeObject(forKey: key)
                    return
                }
                var text = value
                if mergeObjects,
                   let remote = jsonObject(value) as? [String: Any],
                   let current = UserDefaults.standard.data(forKey: key).flatMap({ jsonObject(String(data: $0, encoding: .utf8)) }) as? [String: Any],
                   let merged = jsonString(current.merging(remote) { _, theirs in theirs }) {
                    text = merged
                }
                UserDefaults.standard.set(Data(text.utf8), forKey: key)
            }
        )
    }

    private static func defaultBindings() -> [String: Binding] {
        [
            // The watchlist lives in the App Group so the widgets can read it.
            "mvk_monitored_stops": Binding(
                read: { (appGroup.array(forKey: "mvk_monitored_stops") as? [String]).flatMap(jsonString) },
                write: { value in
                    if let list = jsonObject(value) as? [Any] {
                        appGroup.set(list.compactMap { $0 as? String }, forKey: "mvk_monitored_stops")
                    } else {
                        appGroup.removeObject(forKey: "mvk_monitored_stops")
                    }
                }
            ),
            // The web stores "1"/"0" and treats anything but "0" as on. Both
            // that and an older build's "true"/"false" parse as a Bool here.
            "mvk_watch_nearest_first": Binding(
                read: { (appGroup.object(forKey: "mvk_watch_nearest_first") as? Bool).map { $0 ? "1" : "0" } },
                write: { value in
                    if let flag = jsonObject(value) as? Bool {
                        appGroup.set(flag, forKey: "mvk_watch_nearest_first")
                    } else {
                        appGroup.removeObject(forKey: "mvk_watch_nearest_first")
                    }
                }
            ),
            "mvk_filter_state": dataBinding("mvk_filter_state", mergeObjects: true),
            "mvk_timetable_favorites": dataBinding("mvk_timetable_favorites", mergeObjects: false),
        ]
    }
}

/// Two-way, per-key cloud sync of every `mvk_*` setting (web `lib/sync.ts`,
/// `/v3/sync`).
///
/// - Local change: noticed on every defaults write, pushed after 1.5 s of quiet.
/// - Sign-in on a new device: everything is pulled, then the app reloads once.
/// - Another device's change: the server says so over the WebSocket; pulled.
/// - On conflict the later edit wins, key by key.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    enum State: Equatable { case off, idle, syncing, error }

    @Published private(set) var state: State = .off
    @Published private(set) var lastSyncAt: String?
    @Published var pendingRemote = false
    @Published private(set) var error: String?

    private struct Meta: Codable {
        var lastPull: String?
        var stamps: [String: String] = [:]
        var dirty: [String] = []
    }

    private struct Item: Codable {
        let key: String
        let value: JSONValue?
        var deleted: Bool?
        let updatedAt: String
    }

    private static let metaKey = "mvk_sync_meta"
    /// The value of each key as this engine last saw it — what a local
    /// change is detected against, and the base for merging object values.
    private static let knownKey = "mvk_sync_known"
    private static let remoteKey = "mvk_sync_remote"
    private let pushDebounce: Duration = .milliseconds(1500)
    private let pullInterval: Duration = .seconds(5 * 60)
    private let requestTimeout: TimeInterval = 15

    private var started = false
    private var pulling = false
    private var pullAgain = false
    private var pushTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var known: [String: String]
    private var remote: [String: String]

    private init() {
        known = Self.readDict(Self.knownKey) ?? [:]
        remote = Self.readDict(Self.remoteKey) ?? [:]
    }

    func lastRemote(_ key: String) -> String? { remote[key] }

    // MARK: - Lifecycle

    /// Once, from the app root.
    func start() {
        guard !started else { return }
        started = true
        if Self.readDict(Self.knownKey) == nil { rememberAll() }

        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in CloudSync.shared.scheduleScan() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .mvkSessionChange, object: nil, queue: .main) { _ in
            Task { @MainActor in
                if AccountSession.current != nil { await CloudSync.shared.onLoggedIn() } else { CloudSync.shared.onLoggedOut() }
            }
        })
        // Subscribed even when signed out: the handlers check the session, so a
        // sign-in mid-session is live at once.
        subscription = RealtimeClient.shared.subscribe("sync") { [weak self] _ in
            Task { await self?.refresh() }
        }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pullInterval ?? .seconds(300))
                await self?.refresh()
            }
        }

        guard let session = AccountSession.current else { return }
        state = .idle
        RealtimeClient.shared.authenticate(token: session.sessionToken, deviceId: DeviceIdentity.id)
        let first = readMeta().lastPull == nil
        if first { writeMeta(Meta()) }
        Task {
            let changed = await pull(full: first)
            if first, !changed.isEmpty { AppReloader.shared.reload() } else if !changed.isEmpty { announce(changed) }
        }
    }

    func didBecomeActive() { Task { await refresh() } }

    func didEnterBackground() { BackgroundWork.run("mvk-sync-push") { await self.push() } }

    private func refresh() async {
        let changed = await pull()
        if !changed.isEmpty { announce(changed) }
    }

    func onLoggedIn() async {
        guard let session = AccountSession.current else { return }
        RealtimeClient.shared.authenticate(token: session.sessionToken, deviceId: DeviceIdentity.id)
        // On a new device the cloud wins: the defaults written at launch must
        // not overwrite the real favourites.
        writeMeta(Meta())
        state = .idle
        let changed = await pull(full: true)
        if !changed.isEmpty { AppReloader.shared.reload() }
    }

    func onLoggedOut() {
        RealtimeClient.shared.authenticate(token: nil, deviceId: DeviceIdentity.id)
        writeMeta(Meta())
        state = .off
        lastSyncAt = nil
        pendingRemote = false
        error = nil
        NotificationCenter.default.post(name: .mvkRidesReset, object: nil)
    }

    // MARK: - Local changes

    private func scheduleScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    /// Compares what is stored now with what was last seen; every difference
    /// is a local edit.
    private func scan() {
        let now = SyncRegistry.snapshot()
        var changed: [String] = []
        for (key, value) in now where known[key] != value { changed.append(key) }
        for key in known.keys where now[key] == nil { changed.append(key) }
        guard !changed.isEmpty else { return }
        known = now
        Self.writeDict(Self.knownKey, known)
        var meta = readMeta()
        let stamp = Self.isoNow()
        for key in changed {
            meta.stamps[key] = stamp
            if !meta.dirty.contains(key) { meta.dirty.append(key) }
        }
        writeMeta(meta)
        guard AccountSession.current != nil else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.pushDebounce ?? .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    private func rememberAll() {
        known = SyncRegistry.snapshot()
        Self.writeDict(Self.knownKey, known)
    }

    // MARK: - Push / pull

    func push() async {
        guard AccountSession.current != nil else { return }
        scan()
        let meta = readMeta()
        guard !meta.dirty.isEmpty else { return }
        let keys = meta.dirty
        let items = keys.map { key -> Item in
            let value = SyncRegistry.currentValue(key)
            return Item(key: key, value: value.map(JSONValue.string), deleted: value == nil, updatedAt: meta.stamps[key] ?? Self.isoNow())
        }
        state = .syncing
        do {
            struct Body: Encodable { let deviceId: String; let items: [Item] }
            struct Reply: Decodable { let applied: [String]; let stale: [Item]; let serverTime: String }
            let reply: Reply = try await api("PUT", "/v3/sync", body: Body(deviceId: DeviceIdentity.id, items: items))
            var after = readMeta()
            after.dirty = after.dirty.filter { !keys.contains($0) || after.stamps[$0] != meta.stamps[$0] }
            for key in reply.applied { if let value = SyncRegistry.currentValue(key) { remote[key] = value } }
            let changed = applyRemote(reply.stale, meta: &after)
            writeMeta(after)
            Self.writeDict(Self.remoteKey, remote)
            state = .idle
            lastSyncAt = reply.serverTime
            error = nil
            if !changed.isEmpty { announce(changed) }
        } catch {
            state = .error
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func pull(full: Bool = false) async -> [String] {
        guard AccountSession.current != nil else { return [] }
        if pulling {
            pullAgain = true
            return []
        }
        pulling = true
        state = .syncing
        defer {
            pulling = false
            if pullAgain {
                pullAgain = false
                Task { await refresh() }
            }
        }
        do {
            struct Reply: Decodable { let serverTime: String; let items: [Item] }
            let since = full ? nil : readMeta().lastPull
            var path = "/v3/sync"
            if let since, let encoded = since.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { path += "?since=\(encoded)" }
            let reply: Reply = try await api("GET", path, body: Optional<String>.none)
            var meta = readMeta()
            let changed = applyRemote(reply.items, meta: &meta)
            meta.lastPull = reply.serverTime
            // First sync on this device: what only exists here goes up.
            if full {
                let remoteKeys = Set(reply.items.map(\.key))
                for key in SyncRegistry.snapshot().keys where !remoteKeys.contains(key) && !meta.dirty.contains(key) {
                    meta.dirty.append(key)
                    if meta.stamps[key] == nil { meta.stamps[key] = Self.isoNow() }
                }
            }
            writeMeta(meta)
            Self.writeDict(Self.remoteKey, remote)
            state = .idle
            lastSyncAt = reply.serverTime
            error = nil
            if !meta.dirty.isEmpty { Task { await push() } }
            return changed
        } catch {
            state = .error
            self.error = error.localizedDescription
            return []
        }
    }

    private func applyRemote(_ items: [Item], meta: inout Meta) -> [String] {
        var changed: [String] = []
        for item in items where SyncRegistry.syncable(item.key) {
            let local = meta.stamps[item.key]
            let isDirty = meta.dirty.contains(item.key)
            if let local, local >= item.updatedAt, !isDirty { continue }
            // Newer here: it will be pushed.
            if isDirty, let local, local > item.updatedAt { continue }
            let value = item.deleted == true ? nil : item.value?.storageString
            remote[item.key] = value
            if value == SyncRegistry.currentValue(item.key) {
                meta.stamps[item.key] = item.updatedAt
                continue
            }
            SyncRegistry.write(item.key, value)
            known[item.key] = SyncRegistry.currentValue(item.key)
            meta.stamps[item.key] = item.updatedAt
            meta.dirty.removeAll { $0 == item.key }
            changed.append(item.key)
        }
        Self.writeDict(Self.knownKey, known)
        return changed
    }

    /// Most of the app reads its storage at launch, so a remote change is
    /// announced: taken over at once in the background, offered as a banner
    /// in the foreground.
    private func announce(_ keys: [String]) {
        NotificationCenter.default.post(name: .mvkSyncApplied, object: keys)
        if UIApplication.shared.applicationState != .active {
            AppReloader.shared.reload()
        } else {
            pendingRemote = true
        }
    }

    // MARK: - Transport

    private func api<Body: Encodable, Reply: Decodable>(_ method: String, _ path: String, body: Body?) async throws -> Reply {
        guard let session = AccountSession.current else { throw SyncError.signedOut }
        guard let url = URL(string: APIConfig.baseURLString + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(session.sessionToken, forHTTPHeaderField: "x-account-session")
        request.setValue(DeviceIdentity.id, forHTTPHeaderField: "x-device-id")
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await APIClient.shared.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SyncError.expired }
        guard (200..<300).contains(status) else { throw SyncError.http(status) }
        return try JSONDecoder().decode(Reply.self, from: data)
    }

    enum SyncError: LocalizedError {
        case signedOut, expired, http(Int)
        var errorDescription: String? {
            switch self {
            case .signedOut: return "nincs bejelentkezve"
            case .expired: return "A munkamenet lejárt. Jelentkezz be újra."
            case .http(let code): return "szinkron HTTP \(code)"
            }
        }
    }

    // MARK: - Storage

    private func readMeta() -> Meta {
        guard let raw = UserDefaults.standard.string(forKey: Self.metaKey),
              let meta = try? JSONDecoder().decode(Meta.self, from: Data(raw.utf8))
        else { return Meta() }
        return meta
    }

    private func writeMeta(_ meta: Meta) {
        guard let data = try? JSONEncoder().encode(meta), let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: Self.metaKey)
    }

    private static func readDict(_ key: String) -> [String: String]? {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String]
    }

    private static func writeDict(_ key: String, _ value: [String: String]) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// `Date.toISOString()` — stamps are compared as strings, like the web.
    private static func isoNow() -> String { isoFormatter.string(from: Date()) }
}

/// A synced value as the server returns it: the web posts strings, but any
/// JSON may come back.
enum JSONValue: Codable, Equatable {
    case string(String)
    case other(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .string(text)
            return
        }
        let any = try container.decode(AnyJSON.self)
        let data = try JSONSerialization.data(withJSONObject: any.value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        self = .other(String(data: data, encoding: .utf8) ?? "null")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text): try container.encode(text)
        case .other(let json): try container.encode(json)
        }
    }

    /// The `localStorage` string: a string as is, anything else as JSON text.
    var storageString: String? {
        switch self {
        case .string(let text): return text
        case .other(let json): return json == "null" ? nil : json
        }
    }
}

private struct AnyJSON: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var out: [Any] = []
            while !array.isAtEnd { out.append(try array.decode(AnyJSON.self).value) }
            value = out
        } else if let object = try? decoder.container(keyedBy: AnyKey.self) {
            var out: [String: Any] = [:]
            for key in object.allKeys { out[key.stringValue] = try object.decode(AnyJSON.self, forKey: key).value }
            value = out
        } else {
            let single = try decoder.singleValueContainer()
            if single.decodeNil() { value = NSNull() }
            else if let flag = try? single.decode(Bool.self) { value = flag }
            else if let number = try? single.decode(Double.self) { value = number }
            else { value = try single.decode(String.self) }
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
