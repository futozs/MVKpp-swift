//
//  DelayFormat.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import SwiftUI

/// How far off schedule a departure is. `unknown` is not "on time" — it means
/// the run has no real-time match at all, and the UI must say so rather than
/// implying punctuality.
enum DelayState {
    case ontime, late, early, unknown
}

enum DelayFormat {

    /// Anything inside ±45 s reads as on time; below that the number is noise.
    static let onTimeSec = 45
    /// The delay bar saturates here, so a 6-minute delay and a 40-minute one
    /// do not look the same at a glance.
    static let scaleSec = 360.0

    static func state(_ sec: Int?) -> DelayState {
        guard let sec else { return .unknown }
        if abs(sec) < onTimeSec { return .ontime }
        return sec > 0 ? .late : .early
    }

    /// Compact form for a row: "+3 perc", "−2 perc", "Pontos", "—".
    static func label(_ sec: Int?) -> String {
        switch state(sec) {
        case .unknown: return "—"
        case .ontime: return "Pontos"
        case .late: return "+\(minutes(sec)) perc"
        case .early: return "−\(minutes(sec)) perc"
        }
    }

    /// Full sentence for a detail surface.
    static func sentence(_ sec: Int?) -> String {
        switch state(sec) {
        case .unknown: return "Nincs menetrendi adat"
        case .ontime: return "Menetrend szerint jár"
        case .late: return "\(minutes(sec)) percet késik"
        case .early: return "\(minutes(sec)) perccel siet"
        }
    }

    static func tone(_ sec: Int?) -> Color {
        switch state(sec) {
        case .late: return Theme.late
        case .early: return Theme.early
        case .ontime: return Theme.ontime
        case .unknown: return Theme.mutedForeground
        }
    }

    /// 0…1, how far the bar fills. Zero for on-time and unknown.
    static func magnitude(_ sec: Int?) -> Double {
        switch state(sec) {
        case .late, .early: return min(1, Double(abs(sec ?? 0)) / scaleSec)
        case .ontime, .unknown: return 0
        }
    }

    /// Never rounds down to "0 perc" — once past the on-time band, the
    /// smallest thing worth saying is one minute.
    private static func minutes(_ sec: Int?) -> Int {
        max(1, Int((Double(abs(sec ?? 0)) / 60).rounded()))
    }
}
