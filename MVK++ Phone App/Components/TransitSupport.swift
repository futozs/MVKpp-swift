//
//  TransitSupport.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

/// Tailwind's amber, which the web app uses for "watch out" (run to catch it,
/// the bus starts late, congestion ahead) — neither good news nor an error.
enum TransitTone {
    /// `amber-300`
    static let amber = Color(red: 252 / 255, green: 211 / 255, blue: 77 / 255)
    /// `amber-400`
    static let amberStrong = Color(red: 251 / 255, green: 191 / 255, blue: 36 / 255)
}

/// An API failure in the rider's words: a short reason from the status code
/// instead of the raw error text — the web app's `lib/apiError`.
struct FriendlyError: Equatable {
    let code: Int?
    let reason: String

    init(_ error: Error) {
        if let urlError = error as? URLError {
            code = nil
            reason = urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost
                ? "Nincs internetkapcsolat"
                : "A szerver nem válaszol"
            return
        }
        guard case APIError.badStatus(let status) = error else {
            code = nil
            reason = "A szerver nem válaszol"
            return
        }
        code = status
        switch status {
        case 401, 403: reason = "Nincs hozzáférés"
        case 404: reason = "Ismeretlen megálló vagy adat"
        case 408, 504: reason = "Túl lassú válasz"
        case 429: reason = "Túl sok kérés, kicsit lassítunk"
        case 502, 503: reason = "A szerver most nem érhető el"
        case 500...: reason = "Szerverhiba"
        default: reason = "Váratlan hiba"
        }
    }
}

/// „Hiba, újracsatlakozás…” — the spinning retry notice above a board.
struct RetryNotice: View {
    let error: FriendlyError
    var title = "Hiba, újracsatlakozás…"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.late)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
                }
            Text("\(Text(title).fontWeight(.semibold).foregroundStyle(Theme.foreground)) \(Text(error.reason).foregroundStyle(Theme.mutedForeground))")
                .font(Theme.sans(12))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let code = error.code {
                Text(String(code))
                    .font(Theme.mono(10, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.muted, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.late.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.late.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The Figyelő's switchable features (Beállítások → Megállófigyelő), each its
/// own `mvk_pref_*` key — the web app's `lib/watchPrefs`. All default to on.
@MainActor
final class WatchFeatures: ObservableObject {
    static let shared = WatchFeatures()

    enum Feature: String, CaseIterable {
        case catchBus, leaveTimes, startRisk, traffic, forecast, predictedVehicle, replacement, vehicleTrack, commute

        var key: String {
            switch self {
            case .catchBus: return "mvk_pref_watch_catch"
            case .leaveTimes: return "mvk_pref_watch_leave_times"
            case .startRisk: return "mvk_pref_watch_start_risk"
            case .traffic: return "mvk_pref_watch_traffic"
            case .forecast: return "mvk_pref_watch_forecast"
            case .predictedVehicle: return "mvk_pref_predicted_vehicle"
            case .replacement: return "mvk_pref_watch_replacement"
            case .vehicleTrack: return "mvk_pref_watch_vehicle_track"
            case .commute: return "mvk_pref_watch_commute"
            }
        }
    }

    @Published private(set) var enabled: Set<Feature> = []
    private var observer: AnyCancellable?

    private init() {
        reload()
        observer = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    func isOn(_ feature: Feature) -> Bool { enabled.contains(feature) }

    private func reload() {
        let next = Set(Feature.allCases.filter { LocalStore.shared.bool($0.key) })
        if next != enabled { enabled = next }
    }
}

/// Budapest wall-clock helpers. The service day rolls over at 03:00, as on
/// the server and in GTFS.
enum BudapestClock {
    static let timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current

    private static let hmFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// „08:05” for a unix time.
    static func hm(_ unix: Double) -> String {
        hmFormatter.string(from: Date(timeIntervalSince1970: unix))
    }

    /// „08:05” for a minute of the day.
    static func hm(minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// Minute of the Budapest day, 0–1439.
    static func minute(_ unix: Double) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: unix))
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The service day (`YYYY-MM-DD`) a moment belongs to.
    static func serviceIso(_ unix: Double) -> String {
        let shifted = Date(timeIntervalSince1970: unix - 3 * 3600)
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// ISO weekday of a `YYYY-MM-DD` day: 1 = Monday … 7 = Sunday.
    static func isoDow(_ iso: String) -> Int {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else { return 1 }
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }
}
