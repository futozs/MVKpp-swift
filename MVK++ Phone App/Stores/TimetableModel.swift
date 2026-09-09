//
//  TimetableModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// The timetable's data for one day: which routes run, which runs were pulled,
/// and what the gateway actually observed.
///
/// Everything here is keyed on a date, because the timetable is the one screen
/// that looks backwards as well as forwards.
@MainActor
final class TimetableModel: ObservableObject {

    @Published private(set) var routes: [TimetableRoute] = []
    @Published private(set) var routesError: String?
    @Published private(set) var isLoadingRoutes = false
    /// The board on screen was read off the downloaded pack, not the gateway.
    /// Cancellations and the trip journal are live-only, so they are missing —
    /// the screen says so rather than showing a clean board that isn't.
    @Published private(set) var isOffline = false

    @Published private(set) var cancelledTripIds: Set<String> = []
    @Published private(set) var cancelledTrips: [CancelledTrip] = []
    @Published private(set) var journal: [String: TripJournalEntry] = [:]

    /// Seconds since midnight, ticked every 15 s — drives "next departure",
    /// the current-hour highlight and the past/future split.
    @Published private(set) var nowSec: Int = TimetableModel.secondsSinceMidnight()

    @Published var date: String = TimetableModel.todayIso() {
        didSet {
            guard date != oldValue else { return }
            Task { await reloadForDate() }
        }
    }

    private var clockTask: Task<Void, Never>?
    private var journalTask: Task<Void, Never>?

    // MARK: - Date helpers

    static func todayIso() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// The gateway takes `yyyyMMdd`; the UI works in ISO.
    static func isoToYmd(_ iso: String) -> String {
        iso.replacingOccurrences(of: "-", with: "")
    }

    static func ymdToIso(_ ymd: String) -> String? {
        guard ymd.count == 8 else { return nil }
        let year = ymd.prefix(4)
        let month = ymd.dropFirst(4).prefix(2)
        let day = ymd.dropFirst(6).prefix(2)
        return "\(year)-\(month)-\(day)"
    }

    static func secondsSinceMidnight(_ date: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    var isToday: Bool { date == Self.todayIso() }

    var day: DayRelation { TripStatus.dayRelation(date, todayIso: Self.todayIso()) }

    /// "szept. 5." — the day itself.
    var dateLabel: String { formatted("MMMd") }

    /// "péntek" — spelled out, because a timetable is read by weekday.
    var weekdayLabel: String { formatted("EEEE") }

    private func formatted(_ template: String) -> String {
        guard let parsed = Self.parse(date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: parsed)
    }

    func goToToday() { date = Self.todayIso() }

    static func parse(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }

    func shiftDate(by days: Int, min: String?, max: String?) {
        guard let current = Self.parse(date),
              let next = Calendar.current.date(byAdding: .day, value: days, to: current)
        else { return }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let iso = formatter.string(from: next)

        if let min, iso < min { return }
        if let max, iso > max { return }
        date = iso
    }

    // MARK: - Lifecycle

    func start() async {
        startClock()
        await reloadForDate()
    }

    func stop() {
        clockTask?.cancel()
        clockTask = nil
        journalTask?.cancel()
        journalTask = nil
    }

    private func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await MainActor.run { self?.nowSec = TimetableModel.secondsSinceMidnight() }
            }
        }
    }

    private func reloadForDate() async {
        let ymd = Self.isoToYmd(date)
        async let routesLoad: Void = loadRoutes(ymd: ymd)
        async let cancelledLoad: Void = loadCancelled(ymd: ymd)
        _ = await (routesLoad, cancelledLoad)
        startJournalRefresh(ymd: ymd)
    }

    private func loadRoutes(ymd: String) async {
        isLoadingRoutes = true
        defer { isLoadingRoutes = false }
        do {
            routes = try await APIClient.shared.timetableRoutes(date: ymd).routes
            routesError = nil
            isOffline = false
        } catch {
            // The downloaded pack holds the gateway's own answer for this day,
            // stored verbatim — so the list is the same list, just older.
            if let stored = OfflineScheduleStore.timetableRoutes(ymd: ymd), !stored.routes.isEmpty {
                routes = stored.routes
                routesError = nil
                isOffline = true
            } else {
                routes = []
                isOffline = false
                routesError = OfflineScheduleStore.manifest.isEmpty
                    ? error.localizedDescription
                    : "Erre a napra nincs letöltött menetrend, és a szerver sem érhető el."
            }
        }
    }

    private func loadCancelled(ymd: String) async {
        do {
            let response = try await APIClient.shared.cancelledTrips(date: ymd)
            cancelledTrips = response.trips
            cancelledTripIds = Set(response.tripIds)
        } catch {
            // No cancellation feed just means nothing is struck through.
            cancelledTrips = []
            cancelledTripIds = []
        }
    }

    /// The journal only keeps changing for today; past days are settled and
    /// need one fetch.
    private func startJournalRefresh(ymd: String) {
        journalTask?.cancel()
        let repeats = day == .today

        journalTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.loadJournal(ymd: ymd)
                guard repeats else { return }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func loadJournal(ymd: String) async {
        do {
            journal = try await APIClient.shared.tripJournal(date: ymd).trips
        } catch {
            journal = [:]
        }
    }

    /// How many runs were pulled on each route, for the badge in the list.
    var cancelledCountByRoute: [String: Int] {
        cancelledTrips.reduce(into: [:]) { counts, trip in
            guard !trip.routeId.isEmpty else { return }
            counts[trip.routeId, default: 0] += 1
        }
    }

    deinit {
        clockTask?.cancel()
        journalTask?.cancel()
    }
}
