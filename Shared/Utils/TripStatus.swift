//
//  TripStatus.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// Where a run stands right now. Distinguishing these matters because the app
/// shows a different source for each: `live` reads the vehicle feed, `running`
/// and `finished` fall back to the trip journal, `scheduled` has only the
/// timetable.
enum TripRunState: String {
    case cancelled
    case live
    case running
    case finished
    case scheduled
    case unknown
}

enum DayRelation {
    case past, today, future
}

enum TripStatus {

    /// ISO `yyyy-MM-dd` strings compare correctly lexicographically, so no
    /// date parsing is needed to place a day relative to today.
    static func dayRelation(_ iso: String, todayIso: String) -> DayRelation {
        if iso < todayIso { return .past }
        if iso > todayIso { return .future }
        return .today
    }

    struct RunInput {
        let cancelled: Bool
        let hasLiveVehicle: Bool
        let departureSec: Int
        let arrivalSec: Int
        let nowSec: Int
        let day: DayRelation
    }

    /// Order matters: a past or future day is decided before anything else,
    /// because the live feed only ever describes today.
    static func runState(_ input: RunInput) -> TripRunState {
        if input.day == .past { return .finished }
        if input.day == .future { return .scheduled }
        if input.cancelled { return .cancelled }
        if input.hasLiveVehicle { return .live }
        if input.nowSec > input.arrivalSec { return .finished }
        if input.nowSec >= input.departureSec { return .running }
        return .scheduled
    }

    /// Whether the trip journal's vehicle assignment is worth showing — only
    /// for runs that have actually begun.
    static func showsJournalVehicle(_ state: TripRunState) -> Bool {
        state == .running || state == .finished
    }

    static func runLabel(_ state: TripRunState, vehicleId: String? = nil) -> String? {
        switch state {
        case .cancelled:
            return "Törölve"
        case .live:
            return vehicleId.map { "Úton · \($0)" } ?? "Úton"
        case .running:
            return vehicleId.map { "Úton · \($0)" } ?? "Nincs élő jel"
        case .finished:
            return vehicleId.map { "Menet vége · \($0)" } ?? "Menet vége"
        case .scheduled:
            return "Még nem indult el"
        case .unknown:
            return nil
        }
    }

    /// Past-tense sentence for a completed departure or arrival.
    static func delayPastSentence(_ sec: Int?, kind: Kind) -> String? {
        guard let sec else { return nil }
        let verb = kind == .start ? "indult" : "ért be"
        let min = Int((Double(abs(sec)) / 60).rounded())
        if min < 1 { return "Menetrend szerint \(verb)" }
        return sec > 0
            ? "\(min) percet késve \(verb)"
            : "\(min) perccel korábban \(verb)"
    }

    enum Kind { case start, end }
}
