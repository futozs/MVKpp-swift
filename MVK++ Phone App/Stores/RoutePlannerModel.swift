//
//  RoutePlannerModel.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// Runs the A→B search and annotates the result with measured lateness.
///
/// Two different questions live here. For a moment in the future, MVK's own
/// planner gives the authoritative itinerary. For one in the past it cannot
/// answer at all, so the measured-history estimate takes over — that is how
/// "how late did I actually get in yesterday?" gets a reply.
@MainActor
final class RoutePlannerModel: ObservableObject {

    @Published private(set) var trips: [RoutePlanTrip] = []
    @Published private(set) var delays: [String: RouteDelayInfo] = [:]
    @Published private(set) var historic: SegmentEstimate?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    /// A departure a few minutes back is still "now" as far as the rider is
    /// concerned; only beyond this does the historic path make sense.
    private static let pastBuffer: TimeInterval = 3 * 60

    static func isPast(_ date: Date) -> Bool {
        date.timeIntervalSinceNow < -pastBuffer
    }

    func plan(from: Stop, to: Stop, at: Date) async {
        isLoading = true
        errorMessage = nil
        trips = []
        delays = [:]
        historic = nil
        defer { isLoading = false }

        if Self.isPast(at) {
            await loadHistoric(from: from, to: to, at: at)
            return
        }

        do {
            let plan = try await APIClient.shared.planRoute(
                from: RoutePlanPoint(lat: from.lat, lon: from.lon),
                to: RoutePlanPoint(lat: to.lat, lon: to.lon),
                departureTime: Self.mvkDepartureParam(at)
            )
            let transit = plan.trips.filter { $0.travelProfile == "TRANSIT" }
            trips = transit

            guard !transit.isEmpty else {
                errorMessage = "Nincs tömegközlekedéssel elérhető útvonal ebben az időpontban."
                return
            }

            await loadDelays(for: transit, at: at)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadHistoric(from: Stop, to: Stop, at: Date) async {
        do {
            historic = try await APIClient.shared.segmentEstimate(
                from: from.id,
                to: to.id,
                at: Self.trueUtcIso(at)
            )
        } catch let error as StatsUnavailableError {
            errorMessage = error.reason
        } catch {
            errorMessage = "Erre az útvonalra nincs történeti adatunk ehhez az időponthoz — ez csak olyan megállópárokra működik, amelyeket egyetlen járat közvetlenül, átszállás nélkül összeköt."
        }
    }

    /// One batched call for every distinct (route, boarding stop) pair across
    /// all itineraries, rather than a request per leg.
    private func loadDelays(for trips: [RoutePlanTrip], at: Date) async {
        var unique: [String: RouteDelayLeg] = [:]
        var order: [String] = []

        for trip in trips {
            for leg in trip.legs {
                guard let key = Self.delayKey(leg),
                      let routeShort = leg.routeShortName,
                      let stopId = leg.fromStopId,
                      unique[key] == nil
                else { continue }
                unique[key] = RouteDelayLeg(routeShort: routeShort, stopId: stopId)
                order.append(key)
            }
        }

        guard !order.isEmpty else { return }

        do {
            let response = try await APIClient.shared.routeDelays(
                at: Self.trueUtcIso(at),
                legs: order.compactMap { unique[$0] }
            )
            var map: [String: RouteDelayInfo] = [:]
            for (index, key) in order.enumerated() where response.results.indices.contains(index) {
                map[key] = response.results[index]
            }
            delays = map
        } catch {
            // Without measurements the itinerary still stands; it just shows
            // scheduled times with no punctuality note.
        }
    }

    static func delayKey(_ leg: RoutePlanLeg) -> String? {
        guard !leg.isWalk, let routeShort = leg.routeShortName, let stopId = leg.fromStopId else {
            return nil
        }
        return "\(routeShort)|\(stopId)"
    }

    func delayInfo(for leg: RoutePlanLeg) -> RouteDelayInfo? {
        Self.delayKey(leg).flatMap { delays[$0] }
    }

    // MARK: - Time formats
    //
    // The two backends want different things from the same instant, and
    // getting this wrong silently shifts every result by the UTC offset.

    /// MVK's planner reads `departureTime` literally as *its own* local time
    /// and ignores the trailing "Z". Sending a genuinely converted UTC instant
    /// would move the search two hours earlier in summer — so the local wall
    /// clock digits go out, with a "Z" that is deliberately a lie.
    static func mvkDepartureParam(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date) + "Z"
    }

    /// Our own warehouse wants a real UTC instant.
    static func trueUtcIso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Itinerary timestamps come back as naive local wall-clock strings
    /// ("2026-09-05T16:34:57") — no "Z", no offset. `ISO8601DateFormatter`
    /// refuses those outright, which would leave the raw string on screen, so
    /// the zone-less form is parsed first and read as local time. The zoned
    /// variants are handled too in case the gateway ever starts sending them.
    static func hourMinute(_ iso: String) -> String {
        guard let date = parseItineraryDate(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func parseItineraryDate(_ iso: String) -> Date? {
        let naive = DateFormatter()
        naive.calendar = Calendar(identifier: .gregorian)
        naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = .current

        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            naive.dateFormat = format
            if let date = naive.date(from: iso) { return date }
        }

        let zoned = ISO8601DateFormatter()
        zoned.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return zoned.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    static func minutes(_ sec: Int) -> String {
        "\(Int((Double(sec) / 60).rounded())) perc"
    }

    /// "1 ó 5 p" / "12 p 30 mp" / "45 mp".
    static func duration(_ sec: Int?) -> String {
        guard let sec else { return "—" }
        let s = abs(sec)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h) ó \(m) p" }
        if m > 0 { return "\(m) p \(s % 60) mp" }
        return "\(s) mp"
    }
}
