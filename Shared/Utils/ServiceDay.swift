//
//  ServiceDay.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// GTFS service days, in the `yyyyMMdd` form every gateway endpoint takes.
///
/// A service day is not a calendar day: MVK's last runs are filed under the
/// day they started, so 00:20 on Sunday still belongs to Saturday's timetable.
/// Everything that has to reason about "which day's schedule answers this
/// moment" goes through here.
enum ServiceDay {

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    static func ymd(_ date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    static func date(_ ymd: String) -> Date? {
        formatter.date(from: ymd)
    }

    /// `ymd` moved by whole days, or `ymd` itself if it cannot be parsed.
    static func shifted(_ ymd: String, byDays days: Int) -> String {
        guard let parsed = date(ymd),
              let moved = Calendar.current.date(byAdding: .day, value: days, to: parsed)
        else { return ymd }
        return formatter.string(from: moved)
    }

    /// The `days` service days starting at `start`, inclusive.
    static func range(from start: String, days: Int) -> [String] {
        guard days > 0 else { return [] }
        return (0..<days).map { shifted(start, byDays: $0) }
    }

    /// Every day from `from` to `to` inclusive, capped so a malformed feed
    /// range cannot ask for an unbounded download.
    static func range(from: String, to: String, limit: Int = 60) -> [String] {
        var days: [String] = []
        var cursor = from
        while cursor <= to, days.count < limit {
            days.append(cursor)
            cursor = shifted(cursor, byDays: 1)
        }
        return days
    }

    /// Today's service day in Budapest as `yyyy-MM-dd` (it changes at 3:00,
    /// whatever the device's time zone) — the web's `serviceNow().iso`.
    static func isoToday(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Budapest")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date.addingTimeInterval(-3 * 3600))
    }

    static func secondsSinceMidnight(_ date: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    /// "szept. 10., csütörtök" — how a downloaded day is listed.
    static func label(_ ymd: String) -> String {
        guard let parsed = date(ymd) else { return ymd }
        let display = DateFormatter()
        display.locale = Locale(identifier: "hu_HU")
        display.setLocalizedDateFormatFromTemplate("MMMdEEEE")
        return display.string(from: parsed)
    }
}
