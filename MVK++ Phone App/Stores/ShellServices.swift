//
//  ShellServices.swift
//  MVK++ Phone App
//

import Combine
import Foundation
import UIKit

/// The device's random ID (`mvk_device_id`) — sync, usage and push all key
/// on it. Device-only: it never travels to the cloud.
@MainActor
enum DeviceIdentity {
    static let key = "mvk_device_id"

    static var id: String {
        if let existing = LocalStore.shared.string(key), !existing.isEmpty { return existing }
        let fresh = UUID().uuidString.lowercased()
        LocalStore.shared.set(key, fresh)
        return fresh
    }
}

/// Miskolc's weather for the header (`useWeather`): every 15 minutes.
@MainActor
final class WeatherModel: ObservableObject {
    @Published private(set) var weather: WeatherResponse?
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let fresh = try? await APIClient.shared.weather() { self?.weather = fresh }
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    deinit { task?.cancel() }
}

extension WeatherResponse {
    static func format(_ celsius: Double) -> String { "\(Int(celsius.rounded())) °C" }

    /// "hőérzet 16 °C · szél 12 km/h" — empty when neither is known.
    var extras: String {
        var parts: [String] = []
        if let feelsLikeC { parts.append("hőérzet \(Self.format(feelsLikeC))") }
        if let windKmh { parts.append("szél \(Int(windKmh.rounded())) km/h") }
        return parts.joined(separator: " · ")
    }

    /// "Részben felhős · hőérzet 16 °C · szél 12 km/h"
    var summary: String {
        [text, extras].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Trips most likely being missed right now, for the Statisztika badge
/// (`useLiveIncidents`). Only the "missing now" ones: the day's official
/// cancellations (30+) are too noisy for a badge.
@MainActor
final class LiveIncidentsModel: ObservableObject {
    @Published private(set) var count = 0
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let live = try? await APIClient.shared.liveIncidents() { self?.count = live.missing.count }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    deinit { task?.cancel() }
}

/// The anonymous usage signal to the system hub (`lib/usage.ts`, POST
/// `/v3/usage`): on open, then every minute if a view was opened or the
/// favourites changed, and when the app goes to the background. No location,
/// no IP, no searches.
@MainActor
final class UsageReporter {
    static let shared = UsageReporter()

    /// snapshot field → storage key
    private static let favoriteKeys: [(String, String)] = [
        ("lines", "mvk_timetable_favorites"),
        ("stops", "mvk_monitored_stops"),
        ("statStops", "mvk_stats_favorite_stops"),
        ("vehicles", "mvk_stats_favorite_vehicles"),
        ("parking", "mvk_parking_favorites"),
        ("kiosk", "mvk_kiosk_stops"),
    ]

    private var views: [String: Int] = [:]
    private var lastFavorites: String?
    private var started = false
    private var timer: Task<Void, Never>?

    func start() {
        guard !started else { return }
        started = true
        send(open: true)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.send(open: false)
            }
        }
    }

    func track(_ view: String) {
        views[view, default: 0] += 1
    }

    func flush() { send(open: false) }

    private func favoritesSnapshot() -> [String: Any] {
        var out: [String: Any] = [:]
        for (field, key) in Self.favoriteKeys {
            let raw = SyncRegistry.currentValue(key) ?? "null"
            let parsed = (try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed)) as? [Any]
            out[field] = parsed ?? []
        }
        return out
    }

    private func send(open: Bool) {
        let favorites = favoritesSnapshot()
        let favJSON = (try? JSONSerialization.data(withJSONObject: favorites, options: .sortedKeys)).flatMap { String(data: $0, encoding: .utf8) }
        let favChanged = favJSON != lastFavorites
        if !open, !favChanged, views.isEmpty { return }

        let screen = UIScreen.main.bounds.size
        var body: [String: Any] = [
            "deviceId": DeviceIdentity.id,
            "open": open,
            // A native app is the closest thing to an installed PWA.
            "standalone": true,
            "lang": Locale.preferredLanguages.first ?? "hu-HU",
            "screen": "\(Int(screen.width))x\(Int(screen.height))",
            "views": views,
        ]
        if favChanged { body["favorites"] = favorites }
        views = [:]
        lastFavorites = favJSON

        guard let url = try? APIClient.shared.url(path: "/v3/usage"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if open, let session = AccountSession.current { request.setValue(session.sessionToken, forHTTPHeaderField: "x-account-session") }
        request.httpBody = data
        Task { _ = try? await APIClient.shared.session.data(for: request) }
    }
}
