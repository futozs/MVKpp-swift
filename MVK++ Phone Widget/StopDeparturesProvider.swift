//
//  StopDeparturesProvider.swift
//  MVK++ Phone Widget
//

import AppIntents
import Foundation
import WidgetKit

struct StopDeparturesEntry: TimelineEntry {
    let date: Date
    let stopId: String?
    let stopName: String
    let stopCode: String
    let departures: [DepartureSnapshot]
    let showsVehicle: Bool
    /// Set when there is nothing to count down — no stop chosen, no network,
    /// or a stop that has finished for the night.
    let message: String?
    /// When the numbers were last actually fetched, for the freshness dot.
    let fetchedAt: Date
    /// The rows came off the downloaded timetable because the gateway could
    /// not be reached. Every countdown here is a scheduled time, so the widget
    /// says so rather than letting them pass for predictions.
    var isOffline = false

    static func placeholder(_ date: Date = Date()) -> StopDeparturesEntry {
        StopDeparturesEntry(
            date: date,
            stopId: nil,
            stopName: "Búza tér",
            stopCode: "104",
            departures: [
                DepartureSnapshot(id: "a", route: "1", color: "C8102E", textColor: "FFFFFF",
                                  headsign: "Tiszai pályaudvar", due: date.addingTimeInterval(180),
                                  delaySec: 95, isLive: true, vehicleId: "MVK-412", tripId: "a"),
                DepartureSnapshot(id: "b", route: "2", color: "1FB574", textColor: "FFFFFF",
                                  headsign: "Diósgyőr, városközpont", due: date.addingTimeInterval(480),
                                  delaySec: -20, isLive: true, vehicleId: "MVK-317", tripId: "b"),
                DepartureSnapshot(id: "c", route: "21", color: "0B6FB8", textColor: "FFFFFF",
                                  headsign: "Egyetemváros", due: date.addingTimeInterval(720),
                                  delaySec: nil, isLive: false, vehicleId: nil, tripId: "c"),
            ],
            showsVehicle: true,
            message: nil,
            fetchedAt: date
        )
    }
}

struct StopDeparturesProvider: AppIntentTimelineProvider {

    /// A widget row is only worth drawing if it fits; four is the large
    /// family's capacity and the largest fetch we ever need.
    private let fetchLimit = 5

    func placeholder(in context: Context) -> StopDeparturesEntry {
        .placeholder()
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> StopDeparturesEntry {
        guard !context.isPreview else { return .placeholder() }
        return await entry(for: configuration)
    }

    func timeline(for configuration: SelectStopIntent, in context: Context) async -> Timeline<StopDeparturesEntry> {
        let base = await entry(for: configuration)
        let now = base.date

        // One entry a minute so the countdown actually ticks between the
        // network refreshes WidgetKit is willing to grant us.
        var entries: [StopDeparturesEntry] = []
        for minute in 0..<12 {
            let date = now.addingTimeInterval(Double(minute) * 60)
            let remaining = base.departures.filter { !$0.hasDeparted(at: date) }
            // Once every bus in the snapshot has left, stale rows are worse
            // than an honest blank — stop emitting and wait for the refresh.
            guard minute == 0 || !remaining.isEmpty else { break }
            entries.append(
                StopDeparturesEntry(
                    date: date,
                    stopId: base.stopId,
                    stopName: base.stopName,
                    stopCode: base.stopCode,
                    departures: remaining,
                    showsVehicle: base.showsVehicle,
                    message: remaining.isEmpty ? base.message : nil,
                    fetchedAt: base.fetchedAt,
                    isOffline: base.isOffline
                )
            )
        }

        // Long enough to respect the system's refresh budget, short enough
        // that delays do not go stale. The app also nudges a reload whenever
        // it is open and polling.
        let refresh = now.addingTimeInterval(base.departures.isEmpty ? 10 * 60 : 4 * 60)
        return Timeline(entries: entries, policy: .after(refresh))
    }

    // MARK: - Fetch

    private func entry(for configuration: SelectStopIntent) async -> StopDeparturesEntry {
        let now = Date()

        // Falls back to the stop chosen in Settings, so a freshly dropped
        // widget shows something real before it is configured.
        let stopId = configuration.stop?.id
            ?? UserDefaults(suiteName: FavoritesStore.appGroupID)?.string(forKey: FavoritesStore.widgetStopKey)
            ?? FavoritesStore.storedStopIds.first

        guard let stopId else {
            return empty(now, message: "Koppints ide, és válassz megállót.")
        }

        let cached = SharedStopCache.stop(id: stopId)
        let fallbackName = configuration.stop?.name ?? cached?.name ?? stopId
        // The number printed on the sign is the one embedded in the GTFS id
        // ("SP569" → "569"). `stop.code` is the platform index, which is not
        // what a rider means by "hányas megálló".
        let riderCode = cached?.riderCode ?? configuration.stop?.code ?? stopId.filter(\.isNumber)

        do {
            let response = try await APIClient.shared.arrivals(stopId: stopId, limit: fetchLimit)
            let reference = response.now > 0 ? Date(timeIntervalSince1970: response.now) : now
            let departures = response.arrivals.map { snapshot($0, reference: reference) }

            return StopDeparturesEntry(
                date: now,
                stopId: stopId,
                stopName: response.stop.name ?? fallbackName,
                stopCode: riderCode,
                departures: departures,
                showsVehicle: configuration.showsVehicle,
                message: departures.isEmpty ? "Innen ma már nem indul járat." : nil,
                fetchedAt: now
            )
        } catch {
            // No gateway. The pack the app downloaded is in the same App Group
            // container, and knows when the bus is scheduled — which is the
            // whole point of having downloaded it.
            let scheduled = OfflineDepartures.calls(stopId: stopId, at: now, limit: fetchLimit)
                .map { snapshot($0, at: now) }

            return StopDeparturesEntry(
                date: now,
                stopId: stopId,
                stopName: fallbackName,
                stopCode: riderCode,
                departures: scheduled,
                showsVehicle: configuration.showsVehicle,
                message: scheduled.isEmpty ? offlineMessage(stopId: stopId) : nil,
                fetchedAt: now,
                isOffline: true
            )
        }
    }

    /// Distinguishes "no signal and nothing downloaded" from "downloaded, and
    /// this stop really is finished for the day".
    private func offlineMessage(stopId: String) -> String {
        guard OfflineDepartures.isAvailable else {
            return "Nincs kapcsolat a szerverrel."
        }
        return OfflineDepartures.knowsStop(stopId)
            ? "Nincs kapcsolat — a menetrend szerint innen ma már nem indul járat."
            : "Nincs kapcsolat, és ez a megálló nincs a letöltött menetrendben."
    }

    private func snapshot(_ arrival: ArrivalItem, reference: Date) -> DepartureSnapshot {
        DepartureSnapshot(
            id: arrival.id,
            route: arrival.route,
            color: arrival.color.isEmpty ? "1FB574" : arrival.color,
            textColor: arrival.text.isEmpty ? "FFFFFF" : arrival.text,
            headsign: arrival.headsign,
            due: reference.addingTimeInterval(Double(arrival.etaMin) * 60),
            delaySec: arrival.delaySec,
            isLive: arrival.live,
            vehicleId: arrival.vehicle?.id,
            tripId: arrival.tripId
        )
    }

    private func snapshot(_ call: OfflineCall, at now: Date) -> DepartureSnapshot {
        DepartureSnapshot(
            id: "\(call.tripId)-\(call.scheduledSec)",
            route: call.route.short.isEmpty ? "?" : call.route.short,
            color: call.route.color.isEmpty ? "1FB574" : call.route.color,
            textColor: call.route.text.isEmpty ? "FFFFFF" : call.route.text,
            headsign: call.headsign,
            due: OfflineDepartures.due(call, at: now),
            delaySec: nil,
            isLive: false,
            vehicleId: nil,
            tripId: call.tripId
        )
    }

    private func empty(_ date: Date, message: String) -> StopDeparturesEntry {
        StopDeparturesEntry(
            date: date,
            stopId: nil,
            stopName: "MVK++",
            stopCode: "",
            departures: [],
            showsVehicle: true,
            message: message,
            fetchedAt: date
        )
    }
}
