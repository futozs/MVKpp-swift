//
//  StatsFormat.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// The formatting helpers of `services/statsApi.ts`, with the same output.
enum StatsFormat {

    static let budapest = TimeZone(identifier: "Europe/Budapest") ?? .current
    static let hu = Locale(identifier: "hu_HU")

    /// `1 234 567` — Hungarian grouping (`Intl.NumberFormat("hu-HU")`).
    static func number(_ value: Int) -> String {
        number(Double(value))
    }

    static func number(_ value: Double, maxFraction: Int = 0) -> String {
        let f = NumberFormatter()
        f.locale = hu
        f.numberStyle = .decimal
        f.maximumFractionDigits = maxFraction
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// A number as the web prints it raw in a template string: `42.5`, `42`.
    static func raw(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    /// One decimal at most (`PLAIN`).
    static func plain(_ value: Double) -> String {
        number(value, maxFraction: 1)
    }

    static func duration(_ sec: Double?) -> String {
        guard let sec, sec.isFinite else { return "" }
        let s = Int(abs(sec).rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h) ó \(m) p" }
        if m > 0 { return "\(m) p \(s % 60) mp" }
        return "\(s) mp"
    }

    static func schedTime(_ sec: Int) -> String {
        String(format: "%02d:%02d", (sec / 3600) % 24, (sec % 3600) / 60)
    }

    static func clock(_ unix: Double?) -> String {
        guard let unix, unix > 0 else { return "" }
        let f = DateFormatter()
        f.locale = hu
        f.timeZone = budapest
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: unix))
    }

    static func delay(_ sec: Double?) -> String {
        guard let sec else { return "" }
        if abs(sec) < 45 { return "pontos" }
        let m = abs(sec) / 60
        return "\(sec > 0 ? "+" : "−")\(oneDecimal(m)) p"
    }

    static func km(_ meters: Double?) -> String {
        guard let meters else { return "" }
        return "\(oneDecimal(meters / 1000)) km"
    }

    /// `toFixed(1)` — a point, like the web.
    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// ±minutes with one decimal: `+1.2 p`, `−0.4 p`.
    static func minutes(_ sec: Double?) -> String {
        guard let sec else { return "" }
        return "\(sec >= 0 ? "+" : "−")\(oneDecimal(abs(sec) / 60)) p"
    }

    static func serviceHour(_ hour: Int) -> String {
        hour < 24 ? String(hour) : "\(hour % 24)+"
    }

    /// Today's service day (Budapest, switching at 3:00) on the server clock.
    @MainActor
    static func serviceToday() -> String {
        let now = Date(timeIntervalSince1970: RealtimeClient.shared.serverNow - 3 * 3600)
        return isoDay(now)
    }

    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = budapest
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func shiftDate(_ iso: String, _ days: Int) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = f.date(from: "\(iso)T12:00:00") else { return iso }
        let moved = date.addingTimeInterval(Double(days) * 86400)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: moved)
    }

    /// "Szo" style short weekday of an ISO day, as `toLocaleDateString("hu-HU", { weekday: "short" })`.
    static func shortWeekday(_ iso: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = f.date(from: "\(iso)T12:00:00") else { return "" }
        let out = DateFormatter()
        out.locale = hu
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateFormat = "EEE"
        return out.string(from: date)
    }

    /// Compact axis value: `1,2 E` above a thousand, else one decimal at most.
    static func tick(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return value.formatted(.number.locale(hu).notation(.compactName).precision(.fractionLength(0...1)))
        }
        return plain((value * 10).rounded() / 10)
    }
}

/// One warehouse query: the web's `useStatsQuery`. The data belongs to the
/// key it was fetched for, so switching vehicle or period never leaves the
/// old numbers under the new title.
@MainActor
final class StatsQuery<T>: ObservableObject {
    @Published private(set) var stored: (key: String, data: T)?
    @Published private(set) var loading = true
    @Published private(set) var error: String?
    @Published private(set) var unavailable = false
    @Published private(set) var nonce = 0

    private(set) var currentKey = ""

    var data: T? {
        guard let stored, stored.key == currentKey else { return nil }
        return stored.data
    }

    func reload() { nonce += 1 }

    /// The `.task(id:)` identity: the query key plus the reload counter.
    func taskId(_ key: String, enabled: Bool = true) -> String {
        "\(key)|\(nonce)|\(enabled)"
    }

    func run(key: String, enabled: Bool = true, _ fetch: () async throws -> T) async {
        currentKey = key
        guard enabled else {
            loading = false
            return
        }
        loading = true
        error = nil
        do {
            let value = try await fetch()
            guard !Task.isCancelled else { return }
            stored = (key, value)
            unavailable = false
        } catch is CancellationError {
            return
        } catch is StatsUnavailableError {
            unavailable = true
            error = nil
        } catch {
            if (error as? URLError)?.code == .cancelled || Task.isCancelled { return }
            self.error = error.localizedDescription
        }
        loading = false
    }
}
