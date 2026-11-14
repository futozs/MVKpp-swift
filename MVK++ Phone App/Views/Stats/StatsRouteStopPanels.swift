//
//  StatsRouteStopPanels.swift
//  MVK++ Phone App
//

import SwiftUI

// MARK: - Vonalak

/// Vonalak (web `RoutePanel.tsx`): punctuality, delay and missed runs of one
/// route over a period.
struct StatsRoutePanel: View {
    let routes: [Route]

    @StateObject private var query = StatsQuery<StatsRouteResponse>()
    @State private var short: String?
    @State private var range = "30"

    private static let ranges: [StatsPillItem<String>] = [
        .init(id: "7", label: "7 nap"),
        .init(id: "30", label: "30 nap"),
        .init(id: "90", label: "90 nap"),
    ]

    /// The statistics key: MVK's route number, a regional route's ID.
    private static func key(_ r: Route) -> String { r.key ?? r.short }

    private static func modeOrder(_ r: Route) -> Int {
        switch TransitModes.routeMode(r) {
        case .tram, .bus: return 0
        case .coach: return 1
        case .rail: return 2
        }
    }

    /// Under the pill: the town or depot for Volán, the line for rail.
    private static func sub(_ r: Route) -> String? {
        switch TransitModes.routeMode(r) {
        case .coach: return r.operator_.flatMap { $0.isEmpty ? nil : $0 }
        case .rail:
            guard let colon = r.long.firstIndex(of: ":") else { return r.long }
            return r.long[r.long.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        default: return nil
        }
    }

    private var sorted: [Route] {
        // MVK first, then Volán (by depot), finally the trains.
        routes.sorted { a, b in
            let ma = Self.modeOrder(a), mb = Self.modeOrder(b)
            if ma != mb { return ma < mb }
            let oa = a.operator_ ?? "", ob = b.operator_ ?? ""
            if oa != ob { return oa.localizedStandardCompare(ob) == .orderedAscending }
            return a.short.localizedStandardCompare(b.short) == .orderedAscending
        }
    }

    var body: some View {
        let to = StatsFormat.serviceToday()
        let from = StatsFormat.shiftDate(to, -(Int(range) ?? 30) + 1)
        let current = short ?? routes.first.map(Self.key)
        let key = "\(current ?? "")|\(from)|\(to)"

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                StatsHeading("Vonalak")
                StatsSearchablePicker(
                    items: sorted.map { r in
                        StatsPillItem(id: Self.key(r), label: r.short, sub: Self.sub(r), color: r.color, search: "\(r.long) \(r.operator_ ?? "")")
                    },
                    value: current,
                    onChange: { short = $0 },
                    placeholder: "Vonalszám vagy útvonal, pl. 1 vagy Tiszai"
                )
                StatsPillPicker(items: Self.ranges, value: range, onChange: { range = $0 })
            }

            if current != nil {
                StatsQueryBoundary(query, empty: { $0.days.isEmpty }) { d in
                    content(d)
                }
            }
        }
        .task(id: query.taskId(key, enabled: current != nil)) {
            guard let current else { return }
            await query.run(key: key, enabled: true) { try await APIClient.shared.statsRoute(short: current, from: from, to: to) }
        }
    }

    private struct Merged {
        let date: String
        let runs: Int
        let ghosts: Int
        let bunching: Int
        let events: Int
        let otp: Double?
        let avgDelay: Double?
    }

    /// Only the run count is per direction; the other fields are daily values
    /// repeated on every direction's row — summing them would double them.
    private func merge(_ days: [StatsRouteDay]) -> [Merged] {
        Dictionary(grouping: days, by: \.service_date)
            .sorted { $0.key < $1.key }
            .compactMap { date, rows in
                guard let day = rows.first else { return nil }
                return Merged(
                    date: date,
                    runs: rows.reduce(0) { $0 + $1.runs },
                    ghosts: day.ghost_runs,
                    bunching: day.bunching_n,
                    events: day.events_n,
                    otp: day.otp_pct,
                    avgDelay: day.avg_delay_s
                )
            }
    }

    private func content(_ d: StatsRouteResponse) -> some View {
        let merged = merge(d.days)
        let totalEvents = merged.reduce(0) { $0 + $1.events }
        let totalRuns = merged.reduce(0) { $0 + $1.runs }
        let totalGhosts = merged.reduce(0) { $0 + $1.ghosts }
        let totalBunch = merged.reduce(0) { $0 + $1.bunching }
        let avgOtp: Int? = totalEvents > 0 ? Int((merged.reduce(0.0) { $0 + ($1.otp ?? 0) * Double($1.events) } / Double(totalEvents)).rounded()) : nil
        let avgDelay: Double? = totalEvents > 0 ? (merged.reduce(0.0) { $0 + ($1.avgDelay ?? 0) * Double($1.events) } / Double(totalEvents)).rounded() : nil

        return VStack(alignment: .leading, spacing: 16) {
            StatsTileGrid {
                StatsStatTile(label: "Menetrendtartás", value: avgOtp.map { "\($0)%" } ?? "", sub: "−1…+5 perc ablakban", tone: avgOtp.map { $0 >= 80 ? .ontime : .late } ?? .standard)
                StatsStatTile(label: "Átlagos késés", value: StatsFormat.delay(avgDelay), sub: "\(StatsFormat.number(totalEvents)) megálló-esemény", tone: (avgDelay ?? 0) > 60 ? .late : .ontime)
                StatsStatTile(label: "Kiesett menet", value: String(totalGhosts), sub: "\(totalRuns) teljesítettből", tone: totalGhosts > 0 ? .late : .ontime)
                StatsStatTile(label: "Torlódás", value: String(totalBunch), sub: "két jármű 2 percen belül", tone: totalBunch > 0 ? .late : .ontime)
            }

            StatsChartFrame(title: "Menetrendtartás alakulása") {
                StatsLineChart(data: merged.map { StatsLinePoint(label: String($0.date.dropFirst(5)), value: $0.otp) }, unit: "%")
            }

            StatsChartFrame(title: "Átlagos késés naponta") {
                StatsLineChart(data: merged.map { StatsLinePoint(label: String($0.date.dropFirst(5)), value: $0.avgDelay) }, unit: " mp", zeroLine: true)
            }

            StatsChartFrame(title: "Teljesített és kiesett menetek") {
                if merged.isEmpty {
                    StatsEmptyChart()
                } else {
                    StatsBarChart(
                        data: merged.map { m in
                            StatsBarDatum(label: String(m.date.dropFirst(5)), value: Double(m.runs), tone: m.ghosts > 0 ? Theme.late : Theme.primary, title: "\(m.date): \(m.runs) menet, \(m.ghosts) kiesett")
                        },
                        labelEvery: max(1, Int(ceil(Double(merged.count) / 8)))
                    )
                }
            }
        }
    }
}

// MARK: - Megállók

/// Megállók (web `StopPanel.tsx`): one stop's last two weeks hour by hour.
struct StatsStopPanel: View {
    let stops: [Stop]

    @ObservedObject private var local = LocalStore.shared
    @StateObject private var query = StatsQuery<StatsStopResponse>()
    @State private var search = ""
    @State private var stopId: String?
    @State private var didPickInitial = false

    /// Favourite stops of the statistics — synced like every web key.
    private static let favoritesKey = "mvk_stats_favorite_stops"
    private static let maxFavorites = 40

    private var favoriteIds: [String] { local.stringList(Self.favoritesKey) }

    private func isFavorite(_ id: String) -> Bool { favoriteIds.contains(id) }

    private func toggleFavorite(_ id: String) {
        let list = favoriteIds
        local.setJSON(Self.favoritesKey, isFavorite(id) ? list.filter { $0 != id } : Array((list + [id]).suffix(Self.maxFavorites)))
    }

    /// A station is one item with its platforms (its measurements come
    /// together too).
    private var pickable: [Stop] {
        let ids = Set(stops.map(\.id))
        return stops.filter { s in !(s.parent.map(ids.contains) ?? false) }
    }

    private var favorites: [Stop] {
        let byId = Dictionary(stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return favoriteIds.compactMap { byId[$0] }
    }

    private var matches: [Stop] {
        let t = search.trimmingCharacters(in: .whitespaces).normalizedForSearch
        // Without a query the favourites have their own row; this is the rest.
        guard !t.isEmpty else { return Array(pickable.filter { !favoriteIds.contains($0.id) }.prefix(12)) }
        return Array(pickable.filter { $0.name.normalizedForSearch.contains(t) || $0.id.lowercased().contains(t) }.prefix(12))
    }

    static func kindLabel(_ stop: Stop) -> String {
        let feed = stop.feed ?? TransitModes.feed(ofId: stop.id).rawValue
        if feed == "rail" { return "Vasútállomás" }
        if feed == "coach" { return stop.station ? "Autóbusz-állomás" : "Volán-megálló" }
        return stop.id
    }

    var body: some View {
        let to = StatsFormat.serviceToday()
        let from = StatsFormat.shiftDate(to, -13)
        let key = "\(stopId ?? "")|\(from)|\(to)"

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                StatsHeading("Megállók")
                StatsSearchField(text: $search, placeholder: "Megálló keresése…", clearable: false)
                if !favorites.isEmpty {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.early)
                            Text("KEDVENCEK")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        .fixedSize()
                        pillRow(favorites, allFavorite: true)
                    }
                }
                if matches.isEmpty {
                    Text("Nincs találat.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                } else {
                    pillRow(matches, allFavorite: false)
                }
            }

            if let stopId {
                StatsQueryBoundary(query, empty: { $0.hours.isEmpty }) { d in
                    content(d, stopId: stopId, from: from, to: to)
                }
            } else {
                Text("Válassz megállót.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 40)
                    .statsDashed(radius: 16, fill: Theme.card.opacity(0.5))
            }
        }
        .onAppear {
            // On opening, the first favourite loads.
            guard !didPickInitial else { return }
            didPickInitial = true
            stopId = favoriteIds.first
        }
        .task(id: query.taskId(key, enabled: stopId != nil)) {
            guard let id = stopId else { return }
            await query.run(key: key) { try await APIClient.shared.statsStop(id: id, from: from, to: to) }
        }
    }

    private func pillRow(_ list: [Stop], allFavorite: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(list) { s in
                    stopPill(s, favorite: allFavorite || isFavorite(s.id))
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func stopPill(_ stop: Stop, favorite: Bool) -> some View {
        let active = stop.id == stopId
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 4) {
            Button {
                stopId = stop.id
            } label: {
                HStack(spacing: 6) {
                    Text(stop.name)
                        .lineLimit(1)
                    Text(TransitModes.isRegionalId(stop.id) ? Self.kindLabel(stop) : stop.id)
                        .font(Theme.mono(10, weight: .semibold))
                        .opacity(0.6)
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: 220, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            Button {
                toggleFavorite(stop.id)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(favorite ? (active ? Theme.primaryForeground : Theme.early) : Theme.mutedForeground)
                    .opacity(favorite ? 1 : 0.6)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorite ? "\(stop.name): eltávolítás a kedvencekből" : "\(stop.name): kedvencnek jelölés")
        }
        .foregroundStyle(active ? Theme.primaryForeground : Theme.mutedForeground)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(active ? Theme.primary : Theme.card, in: shape)
        .overlay(shape.strokeBorder(active ? Theme.primary : Theme.border, lineWidth: 1))
    }

    private struct HourRow {
        let hour: Int
        let events: Int
        let avgDelay: Double?
        let otp: Double?
        let dwell: Double?
    }

    private func byHour(_ hours: [StatsStopHour]) -> [HourRow] {
        Dictionary(grouping: hours, by: \.hour)
            .sorted { $0.key < $1.key }
            .map { hour, rows in
                let events = rows.reduce(0) { $0 + $1.events_n }
                func w(_ pick: (StatsStopHour) -> Double?) -> Double? {
                    events > 0 ? (rows.reduce(0.0) { $0 + (pick($1) ?? 0) * Double($1.events_n) } / Double(events)).rounded() : nil
                }
                return HourRow(hour: hour, events: events, avgDelay: w(\.avg_delay_s), otp: w(\.otp_pct), dwell: w(\.avg_dwell_s))
            }
    }

    private func content(_ d: StatsStopResponse, stopId: String, from: String, to: String) -> some View {
        let rows = byHour(d.hours)
        let total = rows.reduce(0) { $0 + $1.events }
        func wAvg(_ pick: (HourRow) -> Double?) -> Double? {
            total > 0 ? (rows.reduce(0.0) { $0 + (pick($1) ?? 0) * Double($1.events) } / Double(total)).rounded() : nil
        }
        let avgOtp = wAvg(\.otp)
        let avgDelay = wAvg(\.avgDelay)
        let avgDwell = wAvg(\.dwell)
        let busiest = rows.max { $0.events < $1.events }
        let selected = stops.first { $0.id == stopId }
        let fav = isFavorite(stopId)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(selected?.name ?? d.name ?? stopId)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Button {
                        toggleFavorite(stopId)
                    } label: {
                        Image(systemName: fav ? "star.fill" : "star")
                            .font(.system(size: 15))
                            .foregroundStyle(fav ? Theme.early : Theme.mutedForeground)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(fav ? "Eltávolítás a kedvencekből" : "Kedvencnek jelölés")
                }
                Text("\(from) – \(to) · \(StatsFormat.number(total)) érkezés")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
            }

            StatsTileGrid {
                StatsStatTile(label: "Menetrendtartás", value: avgOtp.map { "\(Int($0))%" } ?? "", tone: avgOtp.map { $0 >= 80 ? .ontime : .late } ?? .standard)
                StatsStatTile(label: "Átlagos késés", value: StatsFormat.delay(avgDelay), tone: (avgDelay ?? 0) > 60 ? .late : .ontime)
                StatsStatTile(label: "Átlagos állás", value: avgDwell.map { "\(Int($0)) mp" } ?? "", sub: "utasforgalom-proxy")
                StatsStatTile(label: "Legforgalmasabb óra", value: busiest.map { "\(StatsFormat.serviceHour($0.hour)):00" } ?? "", sub: busiest.map { "\($0.events) érkezés" })
            }

            StatsChartFrame(title: "Érkezések óránként") {
                StatsBarChart(
                    data: rows.map { r in
                        StatsBarDatum(label: StatsFormat.serviceHour(r.hour), value: Double(r.events), title: "\(StatsFormat.serviceHour(r.hour)):00 \(r.events) érkezés, pontosság \(r.otp.map { String(Int($0)) } ?? "")%")
                    },
                    labelEvery: 2
                )
            }

            StatsChartFrame(title: "Pontosság óránként") {
                StatsHourHeat(cells: rows.map { r in
                    StatsHourCell(hour: r.hour, value: r.otp, title: "\(StatsFormat.serviceHour(r.hour)):00 pontosság \(r.otp.map { String(Int($0)) } ?? "")%, átlag \(StatsFormat.delay(r.avgDelay))")
                })
            }

            StatsChartFrame(title: "Átlagos késés óránként") {
                if rows.contains(where: { $0.avgDelay != nil }) {
                    StatsBarChart(
                        data: rows.map { r in
                            let v = r.avgDelay ?? 0
                            return StatsBarDatum(
                                label: StatsFormat.serviceHour(r.hour),
                                value: r.avgDelay,
                                tone: v > 60 ? Theme.late : v < -60 ? Theme.early : Theme.ontime,
                                title: "\(StatsFormat.serviceHour(r.hour)):00 \(StatsFormat.delay(r.avgDelay))"
                            )
                        },
                        labelEvery: 2
                    )
                } else {
                    StatsEmptyChart()
                }
            }
        }
    }
}
