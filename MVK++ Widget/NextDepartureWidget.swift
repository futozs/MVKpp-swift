//
//  NextDepartureWidget.swift
//  MVK++ Widget
//

import AppIntents
import SwiftUI
import WidgetKit

struct NextDepartureEntry: TimelineEntry {
    let date: Date
    let stopId: String?
    let stopName: String
    let departures: [DepartureSnapshot]
    let message: String?
    var relevance: TimelineEntryRelevance?

    var next: DepartureSnapshot? { departures.first { !$0.hasDeparted(at: date) } }
    var upcoming: [DepartureSnapshot] { departures.filter { !$0.hasDeparted(at: date) } }

    static func placeholder(_ date: Date = Date()) -> NextDepartureEntry {
        NextDepartureEntry(
            date: date,
            stopId: nil,
            stopName: "Búza tér",
            departures: [
                DepartureSnapshot(id: "a", route: "1", color: "47897B", textColor: "FFFFFF", headsign: "Tiszai pu.",
                                  due: date.addingTimeInterval(180), delaySec: 60, isLive: true, vehicleId: "412", tripId: "a"),
                DepartureSnapshot(id: "b", route: "21", color: "0B6FB8", textColor: "FFFFFF", headsign: "Egyetemváros",
                                  due: date.addingTimeInterval(540), delaySec: nil, isLive: false, vehicleId: nil, tripId: "b"),
            ],
            message: nil
        )
    }
}

/// Fetches one stop's board and spreads it over a minute-by-minute timeline,
/// so the countdown ticks between the refreshes WidgetKit grants.
enum DepartureTimeline {
    static func entry(stopId: String?, fallbackName: String?) async -> NextDepartureEntry {
        let now = Date()
        guard let stopId else {
            return NextDepartureEntry(date: now, stopId: nil, stopName: "MVK++", departures: [], message: "Vegyél fel megállót a Figyelőre")
        }
        let cachedName = fallbackName ?? SharedStopCache.stop(id: stopId)?.name ?? stopId
        do {
            let response = try await APIClient.shared.arrivals(stopId: stopId, limit: 4, boardKey: WatchSharedState.settings.boardKey)
            let departures = DepartureSnapshot.list(response, now: now)
            return NextDepartureEntry(
                date: now,
                stopId: stopId,
                stopName: response.stop.name ?? cachedName,
                departures: departures,
                message: departures.isEmpty ? "Ma már nem indul járat" : nil
            )
        } catch {
            return NextDepartureEntry(date: now, stopId: stopId, stopName: cachedName, departures: [], message: "Nincs kapcsolat")
        }
    }

    static func timeline(from base: NextDepartureEntry) -> Timeline<NextDepartureEntry> {
        var entries: [NextDepartureEntry] = []
        for minute in 0..<15 {
            let date = base.date.addingTimeInterval(Double(minute) * 60)
            var entry = NextDepartureEntry(date: date, stopId: base.stopId, stopName: base.stopName, departures: base.departures, message: base.message)
            guard minute == 0 || entry.next != nil else { break }
            entry.relevance = relevance(entry)
            entries.append(entry)
        }
        let refresh = base.date.addingTimeInterval(base.departures.isEmpty ? 15 * 60 : 5 * 60)
        return Timeline(entries: entries, policy: .after(refresh))
    }

    /// The Smart Stack lifts a departure the rider can still make: most in
    /// the few minutes before the bus, nothing once the board is empty.
    private static func relevance(_ entry: NextDepartureEntry) -> TimelineEntryRelevance {
        guard let next = entry.next else { return TimelineEntryRelevance(score: 0) }
        let minutes = next.minutes(at: entry.date)
        let score: Float = switch minutes {
        case ...1: 60
        case 2...10: 100
        case 11...20: 50
        default: 10
        }
        return TimelineEntryRelevance(score: score, duration: 60)
    }
}

struct NextDepartureProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextDepartureEntry { .placeholder() }

    func snapshot(for configuration: WatchStopConfigIntent, in context: Context) async -> NextDepartureEntry {
        guard !context.isPreview else { return .placeholder() }
        return await entry(for: configuration)
    }

    func timeline(for configuration: WatchStopConfigIntent, in context: Context) async -> Timeline<NextDepartureEntry> {
        DepartureTimeline.timeline(from: await entry(for: configuration))
    }

    func recommendations() -> [AppIntentRecommendation<WatchStopConfigIntent>] {
        WatchStopConfigIntent.presets()
    }

    private func entry(for configuration: WatchStopConfigIntent) async -> NextDepartureEntry {
        let stopId: String?
        if let stop = configuration.stop {
            stopId = stop.id
        } else {
            stopId = await WidgetStopResolver.resolveStopId() ?? FavoritesStore.storedStopIds.first
        }
        return await DepartureTimeline.entry(stopId: stopId, fallbackName: configuration.stop?.name)
    }
}

struct NextDepartureWidgetView: View {
    let entry: NextDepartureEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryCorner: corner
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .widgetURL(entry.stopId.map { DeepLink.stop($0).url } ?? DeepLink.tab(.multistop).url)
    }

    private var circular: some View {
        Group {
            if let next = entry.next {
                let minutes = next.minutes(at: entry.date)
                Gauge(value: Double(max(0, 15 - min(minutes, 15))), in: 0...15) {
                    Text(next.route)
                } currentValueLabel: {
                    Text(minutes <= 0 ? "most" : "\(minutes)")
                        .font(.system(size: minutes <= 0 ? 12 : 18, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Theme.hex(next.color))
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "bus.fill")
                        .font(.title3)
                        .widgetAccentable()
                }
            }
        }
    }

    private var corner: some View {
        Group {
            if let next = entry.next {
                let minutes = next.minutes(at: entry.date)
                Text(minutes <= 0 ? "most" : "\(minutes)'")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .widgetCurvesContent()
                    .widgetLabel {
                        Text("\(next.route) · \(entry.stopName)")
                    }
            } else {
                Image(systemName: "bus.fill")
                    .widgetLabel { Text(entry.message ?? entry.stopName) }
            }
        }
    }

    private var inline: some View {
        Group {
            if let next = entry.next {
                let minutes = next.minutes(at: entry.date)
                Text("\(Image(systemName: "bus.fill")) \(next.route) · \(minutes <= 0 ? "most" : "\(minutes) perc") · \(entry.stopName)")
            } else {
                Text(entry.message ?? entry.stopName)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .widgetAccentable()
                Text(entry.stopName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            if entry.upcoming.isEmpty {
                Text(entry.message ?? "Nincs adat")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.upcoming.prefix(2)) { departure in
                WidgetDepartureLine(departure: departure, date: entry.date)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One departure on a rectangular complication: tile, headsign, delay,
/// countdown.
struct WidgetDepartureLine: View {
    let departure: DepartureSnapshot
    let date: Date

    var body: some View {
        HStack(spacing: 5) {
            Text(departure.route)
                .font(.system(size: departure.route.count > 2 ? 10 : 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.hex(departure.textColor))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .frame(minWidth: 24)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.hex(departure.color)))
                .widgetAccentable()
            Text(departure.headsign)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 2)
            if departure.isLive, DelayFormat.state(departure.delaySec) != .ontime, departure.delaySec != nil {
                Text(DelayFormat.label(departure.delaySec).replacingOccurrences(of: " perc", with: ""))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DelayFormat.tone(departure.delaySec))
            }
            let minutes = departure.minutes(at: date)
            Text(minutes <= 0 ? "most" : Countdown.compact(minutes: minutes))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
        }
    }
}

struct NextDepartureWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKinds.nextDeparture, intent: WatchStopConfigIntent.self, provider: NextDepartureProvider()) { entry in
            NextDepartureWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.card }
        }
        .configurationDisplayName("Következő indulás")
        .description("A kiválasztott vagy a legközelebbi figyelt megálló következő indulásai.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

extension WatchStopConfigIntent {
    /// watchOS has no widget editor: the face picker offers these presets —
    /// "follow me", then each watched stop.
    static func presets() -> [AppIntentRecommendation<WatchStopConfigIntent>] {
        let automatic = AppIntentRecommendation(intent: WatchStopConfigIntent(stop: nil), description: "Legközelebbi figyelt megálló")
        let cache = Dictionary(SharedStopCache.load().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let watched = FavoritesStore.storedStopIds.compactMap { cache[$0] }.map { stop in
            AppIntentRecommendation(intent: WatchStopConfigIntent(stop: StopEntity(stop)), description: LocalizedStringResource(stringLiteral: stop.name))
        }
        return [automatic] + watched
    }
}
