//
//  PlannerFormat.swift
//  MVK++ Phone App
//

import SwiftUI

/// The planner's wording and number formats, ported from the web
/// `routeplanner/format.ts`. Every time reads Budapest wall-clock, matching
/// the timetable, whatever zone the phone is set to.
enum PlannerFormat {

    /// A deviation smaller than this is called on time.
    static let onTimeSec: Double = 60

    static let zone = TimeZone(identifier: "Europe/Budapest") ?? .current

    private static let hungarian = Locale(identifier: "hu_HU")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }

    private static let hmFormatter = formatter("HH:mm")
    private static let hmsFormatter = formatter("HH:mm:ss")
    private static let isoDayFormatter = formatter("yyyy-MM-dd")

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain = ISO8601DateFormatter()

    // MARK: - Time

    static func date(_ iso: String) -> Date? {
        isoFractional.date(from: iso) ?? isoPlain.date(from: iso)
    }

    static func unix(_ iso: String) -> Double {
        date(iso)?.timeIntervalSince1970 ?? 0
    }

    static func hm(_ iso: String) -> String {
        guard let date = date(iso) else { return iso }
        return hmFormatter.string(from: date)
    }

    static func hm(_ unix: Double) -> String {
        hmFormatter.string(from: Date(timeIntervalSince1970: unix))
    }

    static func hms(_ unix: Double) -> String {
        hmsFormatter.string(from: Date(timeIntervalSince1970: unix))
    }

    static func minutes(_ sec: Double) -> String {
        "\(max(1, Int((sec / 60).rounded()))) perc"
    }

    /// The Budapest calendar day (YYYY-MM-DD) of a moment.
    static func localIsoDate(_ unix: Double) -> String {
        isoDayFormatter.string(from: Date(timeIntervalSince1970: unix))
    }

    static func localIsoDate(_ iso: String) -> String {
        localIsoDate(unix(iso))
    }

    /// Today by the server's clock.
    @MainActor static func todayLocalIso() -> String {
        localIsoDate(RealtimeClient.shared.serverNow)
    }

    @MainActor static func nowLocalTime() -> String {
        hm(RealtimeClient.shared.serverNow)
    }

    /// Unix seconds of a Budapest wall-clock day and `HH:MM`.
    static func toUnix(date: String, time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 0
        let minute = parts.count > 1 ? parts[1] : 0
        let day = date.split(separator: "-").compactMap { Int($0) }
        guard day.count == 3 else { return Int(Date().timeIntervalSince1970) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: day[0], month: day[1], day: day[2], hour: hour, minute: minute)
        guard let moment = calendar.date(from: components) else { return Int(Date().timeIntervalSince1970) }
        return Int(moment.timeIntervalSince1970)
    }

    /// Noon of a `YYYY-MM-DD` day in Budapest, for calendar arithmetic.
    static func noon(_ isoDay: String) -> Date? {
        let day = isoDay.split(separator: "-").compactMap { Int($0) }
        guard day.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2], hour: 12))
    }

    static func isoDay(_ date: Date) -> String {
        isoDayFormatter.string(from: date)
    }

    /// „2026. október 20., kedd”
    static func longDate(_ isoDay: String) -> String {
        guard let date = noon(isoDay) else { return isoDay }
        let formatter = DateFormatter()
        formatter.locale = hungarian
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("yMMMMdEEEE")
        return formatter.string(from: date)
    }

    /// „2026. okt. 20.” — the date field's label.
    static func shortDate(_ isoDay: String) -> String {
        guard let date = noon(isoDay) else { return isoDay }
        let formatter = DateFormatter()
        formatter.locale = hungarian
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    static let monthNames = [
        "január", "február", "március", "április", "május", "június",
        "július", "augusztus", "szeptember", "október", "november", "december",
    ]

    /// The -i suffix of a day number: 1-jei, 2-ai, 12-ei, 28-ai …
    private static func daySuffix(_ day: Int) -> String {
        if day == 1 { return "jei" }
        if day == 2 { return "ai" }
        if day % 10 == 0 { return day == 10 ? "ei" : "ai" }
        return [3, 6, 8].contains(day % 10) ? "ai" : "ei"
    }

    /// „a 2026. október 28-ai” — with the article, to drop into a sentence.
    static func dateAdjective(_ isoDay: String) -> String {
        let parts = isoDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return isoDay }
        return "a \(parts[0]). \(monthNames[parts[1] - 1]) \(parts[2])-\(daySuffix(parts[2]))"
    }

    // MARK: - Delay

    enum Tone {
        case late, early, ontime, unknown

        var color: Color {
            switch self {
            case .late: return Theme.late
            case .early: return Theme.early
            case .ontime: return Theme.ontime
            case .unknown: return Theme.mutedForeground
            }
        }
    }

    static func tone(_ sec: Double?) -> Tone {
        guard let sec else { return .unknown }
        if abs(sec) < onTimeSec { return .ontime }
        return sec > 0 ? .late : .early
    }

    /// „+2 p késés” / „pontos” / „−1 p korábban”
    static func delayForecast(_ sec: Double) -> String {
        let t = tone(sec)
        if t == .ontime { return "pontos" }
        let m = Int((abs(sec) / 60).rounded())
        return t == .late ? "+\(m) p késés" : "−\(m) p korábban"
    }

    /// „+4 p”, „−58 mp”, „±0”
    static func delayShort(_ sec: Double) -> String {
        let s = Int(sec.rounded())
        if s == 0 { return "±0" }
        let sign = s > 0 ? "+" : "−"
        let a = abs(s)
        return a < 60 ? "\(sign)\(a) mp" : "\(sign)\(Int((Double(a) / 60).rounded())) p"
    }

    /// „4 p 41 mp”, „58 mp”
    static func spanExact(_ sec: Double) -> String {
        let a = abs(Int(sec.rounded()))
        let m = a / 60
        let s = a % 60
        if m == 0 { return "\(s) mp" }
        return s > 0 ? "\(m) p \(s) mp" : "\(m) p"
    }

    /// „+4 p 41 mp”, „−58 mp”, „pontosan”
    static func delayExact(_ sec: Double) -> String {
        if Int(sec.rounded()) == 0 { return "pontosan" }
        return "\(sec > 0 ? "+" : "−")\(spanExact(sec))"
    }

    /// Transfer margin in whole minutes (rounded down), under a minute in seconds.
    static func marginText(_ sec: Double) -> String {
        let a = abs(Int(sec.rounded()))
        return a < 60 ? "\(a) mp" : "\(a / 60) p"
    }

    // MARK: - Grammar

    /// „a” or „az” before a number written in digits (egy, öt, ezer → az).
    private static func article(for numeric: String) -> String {
        guard let first = numeric.first else { return "a" }
        if first == "5" { return "az" }
        if first == "1", [1, 4, 7].contains(numeric.count) { return "az" }
        return "a"
    }

    static func modeNoun(_ mode: String) -> String {
        switch mode {
        case "TRAM": return "villamos"
        case "COACH": return "Volán-busz"
        case "RAIL": return "vonat"
        default: return "busz"
        }
    }

    private static func modeInstrumental(_ mode: String) -> String {
        switch mode {
        case "TRAM": return "villamossal"
        case "RAIL": return "vonattal"
        default: return "busszal"
        }
    }

    /// A rail leg's tile shows category and number („IC 582”), others the line.
    static func legTileText(_ leg: JourneyLeg) -> String {
        let short = leg.routeShortName ?? ""
        if leg.isRail, let no = leg.trainNo { return "\(short) \(no)" }
        return short
    }

    /// „az 1653-as busszal” / „a 608-as villamossal” / „a(z) LWA-387 jelű busszal”
    static func vehiclePhrase(_ id: String, mode: String) -> String {
        if let first = id.first, first != "0", id.allSatisfy(\.isNumber) {
            return "\(article(for: id))\u{00A0}\(HungarianText.withSuffix(id).replacingOccurrences(of: "-", with: "\u{2011}"))\u{00A0}\(modeInstrumental(mode))"
        }
        if mode == "RAIL" { return "a(z) \(TransitIds.displayVehicleId(id)) járművel" }
        return "a(z) \(TransitIds.displayVehicleId(id)) jelű \(modeInstrumental(mode))"
    }

    // MARK: - Itinerary

    static func transitLegs(_ trip: JourneyTrip) -> [JourneyLeg] {
        trip.legs.filter(\.isTransit)
    }

    /// The walk after alighting from the last vehicle (s).
    static func trailingWalkSec(_ trip: JourneyTrip) -> Double {
        var sum = 0.0
        for leg in trip.legs.reversed() {
            if leg.isTransit { break }
            sum += leg.durationSec
        }
        return sum
    }

    static func walkTotalSec(_ trip: JourneyTrip) -> Double {
        trip.legs.filter { !$0.isTransit }.reduce(0) { $0 + $1.durationSec }
    }

    static func transfersLabel(_ n: Int) -> String {
        n == 0 ? "átszállás nélkül" : "\(n) átszállás"
    }

    static func distance(_ meters: Double) -> String {
        let m = Int(meters.rounded())
        if m < 1000 { return "\(m) m" }
        let km = (meters / 100).rounded() / 10
        let text = km == km.rounded() ? String(Int(km)) : String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
        return "\(text) km"
    }

    /// „1 234” — Hungarian digit grouping.
    static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = hungarian
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }

    static func routeColor(_ hex: String?) -> Color {
        Theme.hex(hex?.isEmpty == false ? hex : "1FB574")
    }
}

extension Text {
    /// Styled runs as one wrapping text (`+` on `Text` is deprecated on iOS 26).
    static func joined(_ parts: Text...) -> Text {
        parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) { Text("\($0)\($1)") }
    }
}
