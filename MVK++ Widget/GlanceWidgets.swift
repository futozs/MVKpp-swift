//
//  GlanceWidgets.swift
//  MVK++ Widget
//

import CoreLocation
import RelevanceKit
import SwiftUI
import WidgetKit

// MARK: - Figyelő glance

struct WatchedStopsEntry: TimelineEntry {
    struct Row: Identifiable {
        let stopId: String
        let name: String
        let next: DepartureSnapshot?
        var id: String { stopId }
    }

    let date: Date
    let rows: [Row]
    let message: String?
    var relevance: TimelineEntryRelevance?
}

/// Every watched stop's next bus in one glance, refreshed in one request.
struct WatchedStopsProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchedStopsEntry {
        let date = Date()
        return WatchedStopsEntry(date: date, rows: [
            .init(stopId: "SP104", name: "Búza tér", next: NextDepartureEntry.placeholder(date).departures.first),
            .init(stopId: "SP1", name: "Debreczeni Márton tér", next: NextDepartureEntry.placeholder(date).departures.last),
        ], message: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchedStopsEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        Task { completion(await fetch()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchedStopsEntry>) -> Void) {
        Task {
            let base = await fetch()
            let entries = (0..<10).map { minute in
                let date = base.date.addingTimeInterval(Double(minute) * 60)
                let soonest = base.rows.compactMap { $0.next?.minutes(at: date) }.min()
                return WatchedStopsEntry(
                    date: date,
                    rows: base.rows,
                    message: base.message,
                    relevance: TimelineEntryRelevance(score: soonest.map { $0 <= 10 ? 60 : 20 } ?? 0, duration: 60)
                )
            }
            completion(Timeline(entries: entries, policy: .after(base.date.addingTimeInterval(5 * 60))))
        }
    }

    private func fetch() async -> WatchedStopsEntry {
        let now = Date()
        let ids = Array(FavoritesStore.storedStopIds.prefix(4))
        guard !ids.isEmpty else {
            return WatchedStopsEntry(date: now, rows: [], message: "Vegyél fel megállót a Figyelőre")
        }
        do {
            let response = try await APIClient.shared.multiArrivals(stopIds: ids, limit: 1, boardKey: WatchSharedState.settings.boardKey)
            let byId = Dictionary(response.results.map { ($0.stop.id, $0) }, uniquingKeysWith: { first, _ in first })
            let rows = ids.map { id in
                let result = byId[id]
                return WatchedStopsEntry.Row(
                    stopId: id,
                    name: result?.stop.name ?? SharedStopCache.stop(id: id)?.name ?? id,
                    next: result.flatMap { DepartureSnapshot.list($0, now: now).first }
                )
            }
            return WatchedStopsEntry(date: now, rows: rows, message: nil)
        } catch {
            return WatchedStopsEntry(date: now, rows: [], message: "Nincs kapcsolat")
        }
    }
}

struct WatchedStopsView: View {
    let entry: WatchedStopsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.rows.isEmpty {
                Label("Figyelő", systemImage: "dot.radiowaves.up.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text(entry.message ?? "Nincs adat")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.rows.prefix(3)) { row in
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let next = row.next, !next.hasDeparted(at: entry.date) {
                        Text(next.route)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.hex(next.color))
                            .widgetAccentable()
                        let minutes = next.minutes(at: entry.date)
                        Text(minutes <= 0 ? "most" : Countdown.compact(minutes: minutes))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(DeepLink.tab(.multistop).url)
    }
}

struct WatchedStopsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.watchedStops, provider: WatchedStopsProvider()) { entry in
            WatchedStopsView(entry: entry)
                .containerBackground(for: .widget) { Theme.card }
        }
        .configurationDisplayName("Figyelő")
        .description("A figyelt megállóid következő indulása egy pillantásra.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Ride

struct RideEntry: TimelineEntry {
    let date: Date
    let ride: WatchRideSnapshot?
    var relevance: TimelineEntryRelevance?

    var minutesToNext: Int? {
        ride?.nextStopDate.map { max(0, Int(($0.timeIntervalSince(date) / 60).rounded(.up))) }
    }
}

/// The ride from the App Group, drawn without asking the network: the app
/// (or the phone, through it) rewrites it and reloads this kind.
struct RideProvider: TimelineProvider {
    func placeholder(in context: Context) -> RideEntry {
        let now = Date().timeIntervalSince1970
        return RideEntry(date: Date(), ride: WatchRideSnapshot(
            rideId: "preview", tripId: "a", vehicleId: "412", route: "1", color: "47897B", textColor: "FFFFFF",
            headsign: "Tiszai pu.", mode: "tram", boardedStopId: nil, boardedStopName: "Búza tér",
            destinationStopId: nil, destinationStopName: "Tiszai pu.", nextStopId: nil, nextStopName: "Városház tér",
            nextStopAt: now + 120, stopsLeft: 4, delaySec: 60, progress: 0.4, boardedAt: now - 300,
            updatedAt: now, ended: false, source: .phone
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (RideEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : RideEntry(date: Date(), ride: WatchSharedState.ride))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RideEntry>) -> Void) {
        let now = Date()
        let ride = WatchSharedState.ride
        guard let ride else {
            completion(Timeline(entries: [RideEntry(date: now, ride: nil, relevance: TimelineEntryRelevance(score: 0))], policy: .never))
            return
        }
        // "Megérkeztél" stays for ten minutes, then the face goes back to
        // offering "Felszálltam".
        if ride.ended {
            let arrived = RideEntry(date: now, ride: ride, relevance: TimelineEntryRelevance(score: 30, duration: 10 * 60))
            let idle = RideEntry(date: Date(timeIntervalSince1970: ride.updatedAt + 10 * 60), ride: nil, relevance: TimelineEntryRelevance(score: 0))
            completion(Timeline(entries: idle.date > now ? [arrived, idle] : [idle], policy: .never))
            return
        }
        let entries = (0..<10).map { minute in
            RideEntry(date: now.addingTimeInterval(Double(minute) * 60), ride: ride, relevance: TimelineEntryRelevance(score: 100, duration: 60))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(10 * 60))))
    }
}

struct RideWidgetView: View {
    let entry: RideEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let ride = entry.ride {
                switch family {
                case .accessoryCircular: circular(ride)
                case .accessoryCorner: corner(ride)
                case .accessoryInline: inline(ride)
                default: rectangular(ride)
                }
            } else {
                idle
            }
        }
        .widgetURL(DeepLink.ride.url)
    }

    private func circular(_ ride: WatchRideSnapshot) -> some View {
        Gauge(value: ride.ended ? 1 : (ride.progress ?? 0)) {
            Text(ride.route)
        } currentValueLabel: {
            if ride.ended {
                Image(systemName: "checkmark")
            } else {
                Text(ride.stopsLeft.map(String.init) ?? ride.route)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(ride.accentColor)
    }

    private func corner(_ ride: WatchRideSnapshot) -> some View {
        Text(ride.ended ? "✓" : (ride.stopsLeft.map(String.init) ?? ride.route))
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: ride.progress ?? 0) {
                    Text(ride.route)
                }
                .tint(ride.accentColor)
            }
    }

    private func inline(_ ride: WatchRideSnapshot) -> some View {
        if ride.ended {
            return Text("\(ride.route) · Megérkeztél")
        }
        let eta = entry.minutesToNext.map { $0 <= 0 ? " · most" : " · \($0) p" } ?? ""
        return Text("\(ride.route) · \(ride.nextStopName ?? ride.headsign)\(eta)")
    }

    private func rectangular(_ ride: WatchRideSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(ride.route)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.hex(ride.textColor))
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.hex(ride.color)))
                    .widgetAccentable()
                Text(ride.ended ? "Megérkeztél" : (ride.isGetOffNext ? "Itt szállsz le" : "Következő"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ride.isGetOffNext ? Theme.amber400 : .secondary)
                Spacer(minLength: 2)
                if let minutes = entry.minutesToNext, !ride.ended {
                    Text(minutes <= 0 ? "most" : "\(minutes) p")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
            }
            Text(ride.ended ? (ride.destinationStopName ?? ride.headsign) : (ride.nextStopName ?? ride.headsign))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
            if !ride.ended {
                Gauge(value: ride.progress ?? 0) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(ride.accentColor)
                if let left = ride.stopsLeft {
                    Text("\(left) megálló · \(ride.destinationStopName ?? ride.headsign)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var idle: some View {
        switch family {
        case .accessoryInline:
            Text("\(Image(systemName: "ticket")) Felszálltam")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "ticket")
                    .font(.title3)
                    .widgetAccentable()
            }
        case .accessoryCorner:
            Image(systemName: "ticket")
                .widgetLabel { Text("Felszálltam") }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("Felszálltam", systemImage: "ticket")
                    .font(.system(size: 14, weight: .semibold))
                    .widgetAccentable()
                Text("Nincs aktív utazás. Koppints, és válaszd ki a buszt.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RideWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.ride, provider: RideProvider()) { entry in
            RideWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.card }
        }
        .configurationDisplayName("Utazás")
        .description("A folyamatban lévő utazás: következő megálló, hány megálló van hátra, és mikor kell leszállni.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

// MARK: - Mai zavarok

struct DisruptionsEntry: TimelineEntry {
    let date: Date
    let counts: Disruptions.Counts?
    let upcoming: Int
    var relevance: TimelineEntryRelevance?

    var total: Int { (counts?.cancelled ?? 0) + (counts?.missing ?? 0) + (counts?.unseen ?? 0) }
}

struct DisruptionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> DisruptionsEntry {
        DisruptionsEntry(date: Date(), counts: Disruptions.Counts(cancelled: 12, missing: 2, unseen: 3, routes: 6), upcoming: 4)
    }

    func getSnapshot(in context: Context, completion: @escaping (DisruptionsEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        Task { completion(await fetch()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DisruptionsEntry>) -> Void) {
        Task {
            var entry = await fetch()
            // Something missing right now is worth surfacing; a quiet day is not.
            entry.relevance = TimelineEntryRelevance(score: (entry.counts?.missing ?? 0) > 0 ? 40 : 0)
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60))))
        }
    }

    private func fetch() async -> DisruptionsEntry {
        let data = try? await APIClient.shared.disruptions(near: Array(FavoritesStore.storedStopIds.prefix(6)))
        return DisruptionsEntry(date: Date(), counts: data?.counts, upcoming: data?.trips.filter(\.upcoming).count ?? 0)
    }
}

struct DisruptionsWidgetView: View {
    let entry: DisruptionsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.late)
                            .widgetAccentable()
                        Text(entry.counts == nil ? "—" : "\(entry.total)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                    }
                }
            case .accessoryCorner:
                Image(systemName: "exclamationmark.triangle.fill")
                    .widgetAccentable()
                    .widgetLabel { Text("Mai zavarok: \(entry.total)") }
            case .accessoryInline:
                Text("\(Image(systemName: "exclamationmark.triangle.fill")) Mai zavarok: \(entry.total)")
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Mai zavarok", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.late)
                        .widgetAccentable()
                    if let counts = entry.counts {
                        Text("\(counts.cancelled) törölve · \(counts.missing) kimarad")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(counts.unseen) nem indult · \(entry.upcoming) még előttünk")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nincs kapcsolat")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(DeepLink.disruptions.url)
    }
}

struct DisruptionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.disruptions, provider: DisruptionsProvider()) { entry in
            DisruptionsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.card }
        }
        .configurationDisplayName("Mai zavarok")
        .description("A ma kimaradó, törölt és el nem indult menetek száma.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

// MARK: - Near a watched stop (Smart Stack relevance)

struct NearbyStopEntry: RelevanceEntry {
    let departures: NextDepartureEntry
}

/// Smart Stack card that shows up by itself when the rider is standing near
/// one of their watched stops — or on the commute — with that stop's board.
struct NearbyStopRelevanceProvider: RelevanceEntriesProvider {
    private static let radiusM: CLLocationDistance = 200

    func relevance() async -> WidgetRelevance<WatchStopConfigIntent> {
        let cache = Dictionary(SharedStopCache.load().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var attributes = FavoritesStore.storedStopIds.compactMap { id -> WidgetRelevanceAttribute<WatchStopConfigIntent>? in
            guard let stop = cache[id] else { return nil }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon),
                radius: Self.radiusM,
                identifier: "mvk-stop-\(stop.id)"
            )
            return WidgetRelevanceAttribute(configuration: WatchStopConfigIntent(stop: StopEntity(stop)), context: .location(region))
        }
        attributes.append(WidgetRelevanceAttribute(configuration: WatchStopConfigIntent(stop: nil), context: .location(inferred: .commute)))
        return WidgetRelevance(attributes)
    }

    func entry(configuration: WatchStopConfigIntent, context: Context) async throws -> NearbyStopEntry {
        if context.isPreview { return NearbyStopEntry(departures: .placeholder()) }
        let stopId: String?
        if let stop = configuration.stop {
            stopId = stop.id
        } else {
            stopId = await WidgetStopResolver.resolveStopId() ?? FavoritesStore.storedStopIds.first
        }
        return NearbyStopEntry(departures: await DepartureTimeline.entry(stopId: stopId, fallbackName: configuration.stop?.name))
    }

    func placeholder(context: Context) -> NearbyStopEntry {
        NearbyStopEntry(departures: .placeholder())
    }
}

struct NearbyStopWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: WidgetKinds.nearbyStop, provider: NearbyStopRelevanceProvider()) { entry in
            NextDepartureWidgetView(entry: entry.departures)
                .containerBackground(for: .widget) { Theme.card }
        }
        .configurationDisplayName("Közeli megálló")
        .description("Magától előjön, amikor egy figyelt megállód közelében vagy.")
    }
}
