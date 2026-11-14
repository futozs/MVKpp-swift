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

/// The service clock the web and the server share: Europe/Budapest whatever
/// the device's zone, the day turning at 03:00, and the seconds counted from
/// GTFS "midnight" (local noon − 12 h), so on a clock-change day a 08:00 run
/// still leaves at 08:00. Callers pass the server's moment, not the device's.
struct ServiceClock: Equatable {
    /// Service day, `yyyy-MM-dd`.
    let iso: String
    let ymd: String
    /// Seconds since the service day's midnight — above 86 400 before 03:00.
    let secOfDay: Int
    let midnightUnix: Int
    /// The wall-clock calendar day.
    let calendarIso: String

    static let cutoffSec = 3 * 3600
    static let timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current

    static func budapestOffset(_ unix: Int) -> Int {
        timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    static func at(_ unix: Int) -> ServiceClock {
        let local = unix + budapestOffset(unix)
        let calSec = ((local % 86_400) + 86_400) % 86_400
        let calendarIso = isoOfUtc(local - calSec)
        let iso = calSec < cutoffSec ? shiftIso(calendarIso, by: -1) : calendarIso
        let midnight = localMidnightUnix(iso)
        return ServiceClock(
            iso: iso,
            ymd: iso.replacingOccurrences(of: "-", with: ""),
            secOfDay: unix - midnight,
            midnightUnix: midnight,
            calendarIso: calendarIso
        )
    }

    static func localMidnightUnix(_ iso: String) -> Int {
        guard let noon = utcNoon(iso) else { return 0 }
        return noon - budapestOffset(noon - 3600) - 43_200
    }

    static func shiftIso(_ iso: String, by days: Int) -> String {
        guard let noon = utcNoon(iso) else { return iso }
        return isoOfUtc(noon + days * 86_400)
    }

    /// Also passes an ISO day through unchanged.
    static func ymdToIso(_ ymd: String) -> String? {
        if ymd.count == 10, ymd.contains("-") { return ymd }
        guard ymd.count == 8 else { return nil }
        return "\(ymd.prefix(4))-\(ymd.dropFirst(4).prefix(2))-\(ymd.dropFirst(6).prefix(2))"
    }

    static func isoToYmd(_ iso: String) -> String {
        iso.replacingOccurrences(of: "-", with: "")
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func isoOfUtc(_ unix: Int) -> String {
        let parts = utcCalendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(unix)))
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    private static func utcNoon(_ iso: String) -> Int? {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = utcCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else { return nil }
        return Int(date.timeIntervalSince1970)
    }
}
