//
//  WatchlistWidget.swift
//  MVK++ Phone Widget
//

import AppIntents
import SwiftUI
import WidgetKit

/// One watched stop's board, frozen at fetch time.
struct WatchlistStop: Identifiable, Hashable {
    let id: String
    let name: String
    let code: String
    let departures: [DepartureSnapshot]

    func upcoming(at date: Date) -> [DepartureSnapshot] {
        departures.filter { !$0.hasDeparted(at: date) }
    }
}

struct WatchlistEntry: TimelineEntry {
    let date: Date
    let stops: [WatchlistStop]
    /// Which stop the small widget shows; the switch button moves it.
    let focus: Int
    let message: String?
    var isOffline = false
    var relevance: TimelineEntryRelevance?

    var focused: WatchlistStop? { stops.isEmpty ? nil : stops[focus % stops.count] }

    static func placeholder(_ date: Date = Date()) -> WatchlistEntry {
        let board = StopDeparturesEntry.placeholder(date)
        return WatchlistEntry(
            date: date,
            stops: [
                WatchlistStop(id: "SP104", name: board.stopName, code: board.stopCode, departures: board.departures),
                WatchlistStop(id: "SP1", name: "Debreczeni Márton tér", code: "1", departures: Array(board.departures.reversed())),
                WatchlistStop(id: "SP487", name: "Városház tér", code: "487", departures: board.departures),
            ],
            focus: 0,
            message: nil
        )
    }
}

/// Figyelő on the home screen: every watched stop in one request, spread
/// over a minute-by-minute timeline so each countdown ticks.
struct WatchlistProvider: TimelineProvider {
    private static let maxStops = 5

    func placeholder(in context: Context) -> WatchlistEntry { .placeholder() }

    func getSnapshot(in context: Context, completion: @escaping (WatchlistEntry) -> Void) {
        if context.isPreview { return completion(.placeholder()) }
        Task { completion(await fetch()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchlistEntry>) -> Void) {
        Task {
            let base = await fetch()
            var entries: [WatchlistEntry] = []
            for minute in 0..<12 {
                let date = base.date.addingTimeInterval(Double(minute) * 60)
                let soonest = base.stops.compactMap { $0.upcoming(at: date).first?.minutes(at: date) }.min()
                guard minute == 0 || soonest != nil else { break }
                var entry = WatchlistEntry(date: date, stops: base.stops, focus: base.focus, message: base.message, isOffline: base.isOffline)
                entry.relevance = TimelineEntryRelevance(score: soonest.map { $0 <= 10 ? 80 : 30 } ?? 0, duration: 60)
                entries.append(entry)
            }
            let refresh = base.date.addingTimeInterval(base.stops.isEmpty ? 15 * 60 : 4 * 60)
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }

    private func fetch() async -> WatchlistEntry {
        let now = Date()
        let ids = Array(FavoritesStore.storedStopIds.prefix(Self.maxStops))
        let focus = WatchlistFocus.index
        guard !ids.isEmpty else {
            return WatchlistEntry(date: now, stops: [], focus: 0, message: "Még nem figyelsz megállót. Koppints, és vegyél fel egyet.")
        }
        let cache = Dictionary(SharedStopCache.load().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        do {
            let response = try await APIClient.shared.multiArrivals(stopIds: ids, limit: 3, boardKey: WatchSharedState.settings.boardKey)
            let byId = Dictionary(response.results.map { ($0.stop.id, $0) }, uniquingKeysWith: { first, _ in first })
            let stops = ids.map { id in
                WatchlistStop(
                    id: id,
                    name: byId[id]?.stop.name ?? cache[id]?.name ?? id,
                    code: cache[id]?.riderCode ?? id.filter(\.isNumber),
                    departures: byId[id].map { DepartureSnapshot.list($0, now: now) } ?? []
                )
            }
            return WatchlistEntry(date: now, stops: stops, focus: focus, message: nil)
        } catch {
            let stops = ids.map { id in
                WatchlistStop(
                    id: id,
                    name: cache[id]?.name ?? id,
                    code: cache[id]?.riderCode ?? id.filter(\.isNumber),
                    departures: OfflineDepartures.arrivals(stopId: id, at: now, limit: 3).map { DepartureSnapshot($0, reference: now) }
                )
            }
            return WatchlistEntry(date: now, stops: stops, focus: focus, message: "Nincs kapcsolat — menetrend szerinti idők.", isOffline: true)
        }
    }
}

/// The small widget's current stop, in the App Group so the switch button
/// (which runs in this extension) and the timeline agree.
enum WatchlistFocus {
    private static let key = "mvk_widget_watchlist_focus"
    private static var suite: UserDefaults { UserDefaults(suiteName: FavoritesStore.appGroupID) ?? .standard }

    static var index: Int { suite.integer(forKey: key) }

    static func advance() {
        let count = max(1, min(FavoritesStore.storedStopIds.count, 5))
        suite.set((index + 1) % count, forKey: key)
    }
}

struct NextWatchedStopIntent: AppIntent {
    static let title: LocalizedStringResource = "Következő figyelt megálló"
    static let description = IntentDescription("A widget a következő figyelt megállóra vált.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        WatchlistFocus.advance()
        return .result()
    }
}

struct RefreshDeparturesIntent: AppIntent {
    static let title: LocalizedStringResource = "Indulások frissítése"
    static let description = IntentDescription("Újra lekéri az élő indulásokat.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Views

struct WatchlistWidgetView: View {
    let entry: WatchlistEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: grid(columns: 2, rows: 1, departures: 2)
        case .systemLarge: list
        default: accessory
        }
    }

    // MARK: Small / StandBy

    /// One stop, the next bus as large as it goes — readable from across
    /// the nightstand in StandBy, where the background is dropped.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let stop = entry.focused {
                HStack(spacing: 4) {
                    Text(stop.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if entry.stops.count > 1 {
                        Button(intent: NextWatchedStopIntent()) {
                            Image(systemName: "chevron.forward.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Következő megálló")
                    }
                }
                if let next = stop.upcoming(at: entry.date).first {
                    Link(destination: DeepLink.trip(tripId: next.tripId, vehicleId: next.vehicleId).url) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                RouteBadge(departure: next, size: 15)
                                Spacer(minLength: 0)
                                BigCountdown(minutes: next.minutes(at: entry.date), size: showsBackground ? 34 : 44)
                            }
                            Text(next.headsign)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.foreground.opacity(0.9))
                                .lineLimit(1)
                            DelayLine(departure: next)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if let after = stop.upcoming(at: entry.date).dropFirst().first {
                        HStack(spacing: 5) {
                            RouteBadge(departure: after, size: 11)
                            Text(after.headsign)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(Countdown.compact(minutes: after.minutes(at: entry.date)))
                                .font(Theme.mono(11, weight: .bold))
                        }
                        .foregroundStyle(Theme.mutedForeground)
                    }
                } else {
                    Spacer(minLength: 0)
                    Text(entry.message ?? "Innen ma már nem indul járat.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                    Spacer(minLength: 0)
                }
            } else {
                emptyState
            }
        }
        .widgetURL(entry.focused.map { DeepLink.watchlist($0.id).url } ?? DeepLink.tab(.multistop).url)
    }

    // MARK: Medium

    private func grid(columns: Int, rows: Int, departures: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.stops.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(entry.stops.prefix(columns * rows)) { stop in
                        stopColumn(stop, departures: departures)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func stopColumn(_ stop: WatchlistStop, departures: Int) -> some View {
        Link(destination: DeepLink.watchlist(stop.id).url) {
            VStack(alignment: .leading, spacing: 5) {
                StopTitle(stop: stop)
                let upcoming = stop.upcoming(at: entry.date)
                if upcoming.isEmpty {
                    Text("Nincs induló járat")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                }
                ForEach(upcoming.prefix(departures)) { departure in
                    HStack(spacing: 5) {
                        RouteBadge(departure: departure, size: 12)
                        Text(departure.headsign)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(departure.minutes(at: entry.date) <= 0 ? "MOST" : Countdown.compact(minutes: departure.minutes(at: entry.date)))
                            .font(Theme.mono(13, weight: .heavy))
                            .foregroundStyle(departure.minutes(at: entry.date) <= 0 ? Theme.primary : Theme.foreground)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Large

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)
            if entry.stops.isEmpty {
                emptyState
            }
            ForEach(Array(entry.stops.prefix(4).enumerated()), id: \.element.id) { index, stop in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.border.opacity(0.6))
                        .frame(height: 1)
                        .padding(.vertical, 7)
                }
                Link(destination: DeepLink.watchlist(stop.id).url) {
                    VStack(alignment: .leading, spacing: 5) {
                        StopTitle(stop: stop)
                        let upcoming = stop.upcoming(at: entry.date)
                        if upcoming.isEmpty {
                            Text("Nincs induló járat")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.mutedForeground)
                        } else {
                            HStack(spacing: 8) {
                                ForEach(upcoming.prefix(3)) { departure in
                                    HStack(spacing: 4) {
                                        RouteBadge(departure: departure, size: 12)
                                        Text(departure.minutes(at: entry.date) <= 0 ? "MOST" : Countdown.compact(minutes: departure.minutes(at: entry.date)))
                                            .font(Theme.mono(14, weight: .heavy))
                                            .foregroundStyle(departure.minutes(at: entry.date) <= 0 ? Theme.primary : Theme.foreground)
                                        DelayDot(departure: departure)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.primary)
            Text("Figyelő")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            if entry.isOffline {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.offline)
                    .accessibilityLabel("Offline — menetrend szerinti idők")
            }
            Spacer(minLength: 4)
            Text(entry.date, style: .time)
                .font(Theme.mono(10, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
            Button(intent: RefreshDeparturesIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.primary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Frissítés")
        }
    }

    private var emptyState: some View {
        Link(destination: DeepLink.tab(.multistop).url) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.primary)
                Text(entry.message ?? "Nincs adat")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Lock screen

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.stops.isEmpty {
                Text(entry.message ?? "Figyelő")
                    .font(.system(size: 12))
            }
            ForEach(entry.stops.prefix(3)) { stop in
                HStack(spacing: 4) {
                    Text(stop.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let next = stop.upcoming(at: entry.date).first {
                        Text(next.route)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                        Text(next.minutes(at: entry.date) <= 0 ? "MOST" : Countdown.compact(minutes: next.minutes(at: entry.date)))
                            .font(Theme.mono(12, weight: .heavy))
                    } else {
                        Text("—")
                    }
                }
            }
        }
        .widgetURL(DeepLink.tab(.multistop).url)
    }
}

private struct StopTitle: View {
    let stop: WatchlistStop

    var body: some View {
        HStack(spacing: 5) {
            if !stop.code.isEmpty {
                Text(stop.code)
                    .font(Theme.mono(10, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Theme.primary.opacity(0.55), lineWidth: 1)
                    )
            }
            Text(stop.name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct RouteBadge: View {
    let departure: DepartureSnapshot
    var size: CGFloat = 13

    var body: some View {
        let scale: CGFloat = departure.route.count > 3 ? 0.72 : (departure.route.count > 2 ? 0.85 : 1)
        Text(departure.route)
            .font(.system(size: size * scale, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.hex(departure.textColor))
            .frame(minWidth: size * 1.9)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: size * 0.45, style: .continuous).fill(Theme.hex(departure.color)))
            .widgetAccentable()
    }
}

private struct BigCountdown: View {
    let minutes: Int
    let size: CGFloat

    var body: some View {
        if minutes <= 0 {
            Text("MOST")
                .font(Theme.mono(size * 0.55, weight: .heavy))
                .foregroundStyle(Theme.primary)
        } else {
            let parts = Countdown.parts(minutes: minutes)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.value)
                    .font(Theme.mono(size, weight: .heavy))
                    .foregroundStyle(Theme.foreground)
                    .minimumScaleFactor(0.6)
                Text(parts.unit == "perc" ? "p" : parts.unit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .lineLimit(1)
        }
    }
}

private struct DelayLine: View {
    let departure: DepartureSnapshot

    var body: some View {
        Text(departure.isLive || departure.delaySec != nil ? DelayFormat.label(departure.delaySec) : "menetrend")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(departure.isLive || departure.delaySec != nil ? DelayFormat.tone(departure.delaySec) : Theme.mutedForeground)
    }
}

private struct DelayDot: View {
    let departure: DepartureSnapshot

    var body: some View {
        if departure.isLive {
            Circle()
                .fill(DelayFormat.tone(departure.delaySec))
                .frame(width: 5, height: 5)
                .accessibilityLabel(DelayFormat.sentence(departure.delaySec))
        }
    }
}

struct WatchlistWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.phoneWatchlist, provider: WatchlistProvider()) { entry in
            WatchlistWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Theme.card, Theme.background], startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Figyelő")
        .description("A figyelt megállóid élő indulásai egy helyen — ugyanaz a lista, mint az appban és a weben.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

#Preview("Small", as: .systemSmall) {
    WatchlistWidget()
} timeline: {
    WatchlistEntry.placeholder()
}

#Preview("Medium", as: .systemMedium) {
    WatchlistWidget()
} timeline: {
    WatchlistEntry.placeholder()
}
