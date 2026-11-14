//
//  Countdown.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// How long until the bus, said the way people say it.
///
/// A live board never looks more than an hour ahead, so minutes were always
/// enough. The downloaded timetable does look further — on a Sunday evening
/// the next 6 may genuinely be five hours out — and "353 p" is not a number
/// anyone reads. Past an hour and a half the wait switches to hours.
enum Countdown {

    /// Where a minute count stops being legible.
    private static let hoursAfterMin = 90

    /// The big number and its unit, split so the two can be typeset at
    /// different sizes.
    /// The phone matches the web, which always counts in minutes; the
    /// watch and widgets switch to hours where minutes stop being legible.
    static func parts(minutes: Int, hours: Bool = true) -> (value: String, unit: String) {
        guard hours, minutes >= hoursAfterMin else { return ("\(minutes)", "perc") }
        return ("\(minutes / 60)ó", "\(minutes % 60) p")
    }

    /// One string, for tight rows: "55 p" or "5ó 53p".
    static func compact(minutes: Int) -> String {
        guard minutes >= hoursAfterMin else { return "\(minutes) p" }
        return "\(minutes / 60)ó \(minutes % 60)p"
    }

    /// Spelled out for VoiceOver.
    static func spoken(minutes: Int, hours allowHours: Bool = true) -> String {
        guard allowHours, minutes >= hoursAfterMin else { return "\(minutes) perc múlva" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0
            ? "\(hours) óra múlva"
            : "\(hours) óra \(rest) perc múlva"
    }
}
