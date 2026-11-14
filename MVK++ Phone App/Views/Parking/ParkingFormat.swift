//
//  ParkingFormat.swift
//  MVK++ Phone App
//

import Foundation

/// Text helpers of the parking view (web `parking/format.ts`).
enum ParkingFormat {
    /// JavaScript's `Math.round`: halves go up, so −2.5 → −2.
    static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    private static let budapestHM: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.timeZone = TimeZone(identifier: "Europe/Budapest")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// unix → "18:42" in Budapest time.
    static func clock(_ unix: Double) -> String {
        budapestHM.string(from: Date(timeIntervalSince1970: unix))
    }

    /// Second of the service day → "18:42" (0–23 h after midnight too).
    static func hm(daySec: Int) -> String {
        let s = ((daySec % 86_400) + 86_400) % 86_400
        return String(format: "%02d:%02d", s / 3600, (s % 3600) / 60)
    }

    /// Elapsed time: "most", "7 p", "1 ó 12 p".
    static func duration(_ sec: Double) -> String {
        if sec < 60 { return "most" }
        let m = Int(sec / 60)
        if m < 60 { return "\(m) p" }
        let h = m / 60
        return m % 60 != 0 ? "\(h) ó \(m % 60) p" : "\(h) ó"
    }

    /// How long until the tipped trip starts (negative: it should have left).
    static func until(_ tip: ParkingTripTip, midnight: Double, now: Double) -> Double {
        midnight + Double(tip.startS) - now
    }

    static func untilText(_ sec: Double) -> String {
        if sec <= -60 { return "\(Int((-sec / 60).rounded())) p késésben" }
        if sec < 60 { return "most indul" }
        return "\(duration(sec)) múlva"
    }

    static func pct(_ x: Double) -> String {
        "\(Int((x * 100).rounded()))%"
    }

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Days elapsed between two ISO days.
    static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let a = isoDay.date(from: from), let b = isoDay.date(from: to) else { return 0 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    static func reasonLabel(_ reason: ParkingDepotReason) -> String {
        switch reason {
        case .pullIn: return "Beállt ma"
        case .seen: return "A telephelyen látszik"
        case .timeout: return "Elnémult, beállt"
        case .notToday: return "Ma még nem volt kint"
        }
    }

    static func reasonHint(_ reason: ParkingDepotReason) -> String {
        switch reason {
        case .pullIn: return "G-járattal (garázsmenettel) ért be a telephelyre"
        case .seen: return "élő GPS-jellel a telephelyen áll"
        case .timeout: return "a végállomáson 1 óránál tovább néma volt, kikapcsolva ment vissza"
        case .notToday: return "ma még egy menetet sem vitt"
        }
    }

    /// One line on a vehicle standing in a depot.
    static func depotLine(_ v: ParkingVehicle, history: ParkingFleetHistory?, serviceDate: String) -> String {
        if v.reason == .pullIn, let since = v.since { return "beállt \(clock(since))" }
        if v.reason == .seen { return "itt áll, élő jel" }
        if v.reason == .timeout, let lastSeen = v.lastSeen { return "\(clock(lastSeen)) óta néma" }
        guard let last = history?.lastDate else { return "régóta nem volt kint" }
        let d = daysBetween(last, serviceDate)
        // Out yesterday → today is the first rest day; that is not spelled out.
        return d <= 1 ? "tegnap még kint volt" : "\(d). napja pihen"
    }
}
