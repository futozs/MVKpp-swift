//
//  ScheduleTime.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// Timetable clock strings, and what they become once a delay is applied.
///
/// A printed departure of 18:10 on a run that is two minutes down is really
/// 18:12, and that is the number the rider needs — the schedule alone stops
/// being the answer the moment the feed says otherwise.
enum ScheduleTime {

    /// Parses "HH:MM" into minutes past midnight. GTFS runs past 24:00 for
    /// after-midnight service, so hours above 23 are accepted and kept.
    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...47).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    static func format(minutesPastMidnight: Int) -> String {
        let wrapped = ((minutesPastMidnight % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    /// The scheduled time moved by the run's deviation. Returns nil when there
    /// is no deviation worth showing — under a minute is noise, and repeating
    /// the same number twice would only add clutter.
    static func shifted(_ hhmm: String, bySeconds deviationSec: Int?) -> String? {
        guard let deviationSec, abs(deviationSec) >= 60, let base = minutes(hhmm) else { return nil }
        let shift = Int((Double(deviationSec) / 60).rounded())
        guard shift != 0 else { return nil }
        return format(minutesPastMidnight: base + shift)
    }
}
