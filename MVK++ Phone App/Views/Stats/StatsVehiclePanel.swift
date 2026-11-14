//
//  StatsVehiclePanel.swift
//  MVK++ Phone App
//

import SwiftUI

/// Járművek (web `VehiclePanel.tsx`): one vehicle's day — runs, track,
/// route mix and incident history.
struct StatsVehiclePanel: View {
    let routes: [Route]

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject private var local = LocalStore.shared

    @StateObject private var listQ = StatsQuery<StatsVehicleList>()
    @StateObject private var detailQ = StatsQuery<StatsVehicleDetail>()
    @StateObject private var trackQ = StatsQuery<StatsVehicleTrack>()
    @StateObject private var routesQ = StatsQuery<StatsVehicleRoutes>()
    @StateObject private var incQ = StatsQuery<StatsVehicleIncidents>()

    @State private var vehicleId: String?
    /// The chosen day per vehicle: a new vehicle opens on the last day it
    /// actually ran (the server decides), never an empty one.
    @State private var dateSel: (vehicle: String?, date: String?) = (nil, nil)

    private static let favoritesKey = "mvk_stats_favorite_vehicles"
    private static let maxFavorites = 40
    private static let kindSub = ["TRAM": "villamos", "COACH": "Volán", "RAIL": "vonat"]

    private var modesKey: String { local.modesParam }
    private var date: String? { dateSel.vehicle == vehicleId ? dateSel.date : nil }

    private var favorites: [String] { Array(local.stringList(Self.favoritesKey).prefix(Self.maxFavorites)) }

    private func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    private func toggleFavorite(_ id: String) {
        var list = favorites
        if list.contains(id) {
            list.removeAll { $0 == id }
        } else {
            guard list.count < Self.maxFavorites else { return }
            list.append(id)
        }
        local.setJSON(Self.favoritesKey, list)
    }

    /// The statistics key of a regional route is its ID; the label wants the
    /// short name.
    private var routeLabel: (String) -> String {
        let byKey = Dictionary(routes.compactMap { r in r.key.flatMap { $0 != r.short ? ($0, r.short) : nil } }, uniquingKeysWith: { first, _ in first })
        return { byKey[$0] ?? $0 }
    }

    var body: some View {
        let shownDate = detailQ.data?.vehicleId == vehicleId ? detailQ.data?.date : nil
        let days = detailQ.data?.vehicleId == vehicleId ? (detailQ.data?.days ?? []) : []

        VStack(alignment: .leading, spacing: 16) {
            StatsQueryBoundary(listQ, empty: { $0.vehicles.isEmpty }) { d in
                VStack(alignment: .leading, spacing: 8) {
                    StatsHeading("Járművek")
                    StatsSearchablePicker(
                        items: pickerItems(d.vehicles),
                        value: vehicleId,
                        onChange: { vehicleId = $0 },
                        placeholder: modesKey.contains("coach") || modesKey.contains("rail") ? "Rendszám vagy pályaszám, pl. 1641, LWA387" : "Rendszám, pl. 1641",
                        isFavorite: isFavorite,
                        onToggleFavorite: toggleFavorite,
                        groupLabel: "Jármű keresése"
                    )
                }
            }

            if let vehicleId {
                dayBar(vehicleId: vehicleId, shownDate: shownDate, days: days)

                StatsQueryBoundary(detailQ) { d in
                    detail(d)
                }

                StatsChartFrame(
                    title: "Napi nyomvonal",
                    hint: trackQ.data.map { "\($0.points) pont (\($0.ofTotal) mérésből ritkítva)" } ?? "GPS-pontok a nap folyamán"
                ) {
                    if let track = trackQ.data {
                        StatsTrackTrace(track: track.track)
                    } else {
                        StatsEmptyChart(text: "Betöltés…")
                    }
                }

                StatsChartFrame(title: "Milyen vonalakon jár?") {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.mutedForeground)
                } content: {
                    routeShare
                }

                StatsChartFrame(title: "Üzemzavar-előélet") {
                    incidentHistory
                }
            }
        }
        .task(id: listQ.taskId(modesKey)) {
            let modes = modesKey
            await listQ.run(key: modes) { try await APIClient.shared.statsVehicles(modes: modes) }
            if vehicleId == nil, let first = listQ.data?.vehicles.first { vehicleId = first.vehicle_id }
        }
        .task(id: detailQ.taskId("\(vehicleId ?? "")|\(date ?? "")", enabled: vehicleId != nil)) {
            let id = vehicleId ?? ""
            let day = date ?? ""
            await detailQ.run(key: "\(id)|\(day)", enabled: vehicleId != nil) {
                try await APIClient.shared.statsVehicle(id: id, date: day)
            }
        }
        .task(id: trackQ.taskId("\(vehicleId ?? "")|\(shownDate ?? "")", enabled: vehicleId != nil && shownDate != nil)) {
            let id = vehicleId ?? ""
            let day = shownDate ?? ""
            await trackQ.run(key: "\(id)|\(day)", enabled: vehicleId != nil && shownDate != nil) {
                try await APIClient.shared.statsVehicleTrack(id: id, date: day, every: 2)
            }
        }
        .task(id: routesQ.taskId(vehicleId ?? "", enabled: vehicleId != nil)) {
            let id = vehicleId ?? ""
            await routesQ.run(key: id, enabled: vehicleId != nil) { try await APIClient.shared.statsVehicleRoutes(id: id) }
        }
        .task(id: incQ.taskId(vehicleId ?? "", enabled: vehicleId != nil)) {
            let id = vehicleId ?? ""
            await incQ.run(key: id, enabled: vehicleId != nil) { try await APIClient.shared.statsVehicleIncidents(id: id) }
        }
    }

    private func pickerItems(_ vehicles: [StatsVehicleListItem]) -> [StatsPillItem<String>] {
        vehicles
            .enumerated()
            .sorted { a, b in
                // Favourites first, then MVK's fleet, then Volán and the trains.
                let fa = isFavorite(a.element.vehicle_id) ? 0 : 1
                let fb = isFavorite(b.element.vehicle_id) ? 0 : 1
                if fa != fb { return fa < fb }
                let ra = TransitModes.isRegionalId(a.element.vehicle_id) ? 1 : 0
                let rb = TransitModes.isRegionalId(b.element.vehicle_id) ? 1 : 0
                if ra != rb { return ra < rb }
                return a.offset < b.offset
            }
            .map { v in
                StatsPillItem(
                    id: v.element.vehicle_id,
                    label: TransitModes.displayVehicleId(v.element.vehicle_id),
                    sub: Self.kindSub[v.element.kind],
                    search: v.element.vehicle_id
                )
            }
    }

    // MARK: - Day stepper

    private func dayBar(vehicleId: String, shownDate: String?, days: [String]) -> some View {
        let prevDay = shownDate.flatMap { s in days.first { $0 < s } }
        let nextDay = shownDate.flatMap { s in days.reversed().first { $0 > s } }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Button {
                    if let prevDay { dateSel = (vehicleId, prevDay) }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(StatsButtonStyle(icon: true))
                .disabled(prevDay == nil)
                .accessibilityLabel("Előző nap, amikor közlekedett")

                Menu {
                    ForEach(days, id: \.self) { d in
                        Button("\(d) · \(StatsFormat.shortWeekday(d))") { dateSel = (vehicleId, d) }
                    }
                } label: {
                    Text(shownDate.map { "\($0) · \(StatsFormat.shortWeekday($0))" } ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                        .frame(minWidth: 140, minHeight: 36)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                }
                .disabled(days.isEmpty)
                .accessibilityLabel("Nap választása")

                Button {
                    if let nextDay { dateSel = (vehicleId, nextDay) }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(StatsButtonStyle(icon: true))
                .disabled(nextDay == nil)
                .accessibilityLabel("Következő nap, amikor közlekedett")

                if !days.isEmpty {
                    Text("\(days.count) nap adat")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.leading, 4)
                }
            }

            Button {
                navigation.focusVehicleOnMap(vehicleId, vehicle: store.vehicle(id: vehicleId))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                    Text("Élőben a térképen")
                }
            }
            .buttonStyle(StatsButtonStyle(variant: .ghost))
        }
    }

    // MARK: - Detail

    private func detail(_ d: StatsVehicleDetail) -> some View {
        let s = d.summary
        let stopped: Double = s.map { s in
            s.moving_s.map { max(0, s.service_s - $0) } ?? min(s.service_s, s.dwell_s)
        } ?? 0
        return VStack(alignment: .leading, spacing: 16) {
            StatsTileGrid {
                StatsStatTile(label: "Menet", value: String(s?.runs ?? d.runs.count), sub: "\(s.map { String($0.routes_n) } ?? "") vonalon")
                StatsStatTile(label: "Megtett út", value: StatsFormat.km(s?.dist_m))
                StatsStatTile(label: "Üzemidő", value: StatsFormat.duration(s?.service_s), sub: "ebből állva \(StatsFormat.duration(stopped))")
                StatsStatTile(
                    label: "Átlagos késés",
                    value: StatsFormat.delay(s?.avg_delay_s),
                    sub: s?.p85_delay_s.map { "p85: \(StatsFormat.delay($0))" },
                    tone: (s?.avg_delay_s ?? 0) > 60 ? .late : .ontime
                )
            }

            if let s {
                StatsTileGrid {
                    StatsStatTile(label: "Első pont", value: StatsFormat.clock(s.first_ts))
                    StatsStatTile(label: "Utolsó pont", value: StatsFormat.clock(s.last_ts))
                    StatsStatTile(label: "Csúcssebesség", value: s.max_speed_dms.map { "\(Int(($0 / 10 * 3.6).rounded())) km/h" } ?? "")
                    StatsStatTile(label: "Hiányos menet", value: String(s.gaps_n), sub: "részleges vagy megszakadt", tone: s.gaps_n > 0 ? .late : .ontime)
                }
            }

            StatsChartFrame(title: "A nap menetei") {
                StatsRunTimeline(runs: d.runs, label: routeLabel)
                    .accessibilityLabel("A nap menetei idővonalon")
            }

            if !d.runs.isEmpty {
                StatsChartFrame(title: "Menetek részletesen", hint: "\(d.runs.count) menet ezen a napon") {
                    runTable(d.runs)
                }
            }
        }
    }

    private func runTable(_ runs: [StatsVehicleRun]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    th("Vonal")
                    th("Terv")
                    th("Tény")
                    th("Késés").gridColumnAlignment(.trailing)
                    th("Megálló").gridColumnAlignment(.trailing)
                    th("Állapot").gridColumnAlignment(.trailing)
                }
                Divider().overlay(Theme.border)
                ForEach(Array(runs.enumerated()), id: \.element.id) { i, r in
                    GridRow {
                        Text(routeLabel(r.route_short))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(minWidth: 32)
                            .background(r.color.map { Theme.hex($0) } ?? Theme.primary, in: RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                        Text(StatsFormat.schedTime(r.sched_start_s))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(8)
                        Text(StatsFormat.clock(r.actual_start))
                            .padding(8)
                        Text(StatsFormat.delay(r.start_delay_s))
                            .fontWeight(.semibold)
                            .foregroundStyle(delayColor(r.start_delay_s))
                            .padding(8)
                        Text("\(r.stops_seen)/\(r.stops_total)")
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(8)
                        Text(status(r))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(8)
                    }
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                    if i < runs.count - 1 { Divider().overlay(Theme.border) }
                }
            }
            .frame(minWidth: 544, alignment: .leading)
        }
    }

    private func th(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.mutedForeground)
            .padding(8)
    }

    private func delayColor(_ s: Double?) -> Color {
        guard let s else { return Theme.mutedForeground }
        return s > 45 ? Theme.late : s < -45 ? Theme.early : Theme.ontime
    }

    private func status(_ r: StatsVehicleRun) -> String {
        switch r.status {
        case "complete": return "teljes"
        case "partial": return "részleges \(r.quality)%"
        case "running": return "fut"
        case "ghost": return "kiesett"
        default: return "megszakadt"
        }
    }

    // MARK: - Route share

    @ViewBuilder
    private var routeShare: some View {
        // Rows come per month and route: the ring shows the latest month,
        // otherwise a route would appear several times.
        let all = routesQ.data?.routes ?? []
        let latest = all.first.map { first in all.filter { $0.period_ym == first.period_ym } } ?? []
        if let first = latest.first {
            StatsDonut(
                slices: latest.map { StatsDonutSlice(label: "\(routeLabel($0.route_short)) \($0.runs) menet", value: Double($0.runs), color: $0.color) },
                centerLabel: "\(StatsFormat.raw(first.share_pct))%",
                centerSub: "\(latest.reduce(0) { $0 + $1.runs }) menet ebben a hónapban, \(first.days_active) aktív nap"
            )
        } else {
            StatsEmptyChart(text: "Még nincs havi összegzés ehhez a járműhöz.")
        }
    }

    // MARK: - Incidents

    @ViewBuilder
    private var incidentHistory: some View {
        if let incidents = incQ.data?.incidents, !incidents.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(incidents.prefix(12).enumerated()), id: \.element.id) { i, inc in
                    if i > 0 { Divider().overlay(Theme.border) }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "wrench")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(incidentTitle(inc.kind))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.foreground)
                            if let note = inc.note {
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(inc.kind == "absence" && inc.absent_days != nil ? "\(inc.absent_days ?? 0) nap" : StatsFormat.duration(inc.duration_s))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.foreground)
                            Text("\(String(inc.service_date.dropFirst(5))) · \(inc.confidence)%")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ontime)
                Text("Ehhez a járműhöz nincs rögzített üzemzavar.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func incidentTitle(_ kind: String) -> String {
        switch kind {
        case "mid_trip_stop": return "Menet közben elnémult"
        case "stuck": return "Helyben állt"
        case "no_signal": return "Adatkiesés (nincs térerő)"
        case "absence": return "Kiesett a flottából"
        default: return "Korai bevonás"
        }
    }
}

// MARK: - Run timeline

struct StatsRunTimeline: View {
    let runs: [StatsVehicleRun]
    let label: (String) -> String

    @State private var picked: Int?

    private let rowH: CGFloat = 26
    private let labelW: CGFloat = 44

    var body: some View {
        if runs.isEmpty {
            StatsEmptyChart(text: "Ezen a napon nem futott menet.")
        } else {
            let minS = runs.map(\.sched_start_s).min() ?? 0
            let maxS = runs.map(\.sched_end_s).max() ?? 1
            let span = Double(max(maxS - minS, 1))
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    let track = geo.size.width - labelW - 8
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(runs.enumerated()), id: \.element.id) { i, r in
                            let x = labelW + Double(r.sched_start_s - minS) / span * track
                            let w = max(3, Double(r.sched_end_s - r.sched_start_s) / span * track)
                            let y = CGFloat(i) * rowH + 4
                            Text(StatsFormat.schedTime(r.sched_start_s))
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(Theme.mutedForeground)
                                .offset(x: 0, y: y + 1)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(r.color.map { Theme.hex($0) } ?? Theme.primary)
                                .opacity(r.status == "ghost" ? 0.25 : 0.85)
                                .frame(width: w, height: 16)
                                .overlay(alignment: .leading) {
                                    if w > 26 {
                                        Text(label(r.route_short))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Theme.background)
                                            .lineLimit(1)
                                            .padding(.leading, 6)
                                    }
                                }
                                .overlay {
                                    if picked == i {
                                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.foreground.opacity(0.7), lineWidth: 1.5)
                                    }
                                }
                                .offset(x: x, y: y)
                                .onTapGesture { picked = picked == i ? nil : i }
                        }
                    }
                }
                .frame(height: CGFloat(runs.count) * rowH + 18)

                if let picked, let r = runs[statsSafe: picked] {
                    Text("\(label(r.route_short)) · \(r.headsign ?? "")\nterv \(StatsFormat.schedTime(r.sched_start_s))–\(StatsFormat.schedTime(r.sched_end_s)) · megálló \(r.stops_seen)/\(r.stops_total) (\(r.quality)%) · indulási késés: \(StatsFormat.delay(r.start_delay_s))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.muted.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

// MARK: - Track trace

struct StatsTrackTrace: View {
    let track: [StatsTrackPoint]

    private static let fastDms = 100.0

    var body: some View {
        if track.count < 2 {
            StatsEmptyChart(text: "Ehhez a naphoz nincs elég GPS-pont.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Canvas { ctx, size in draw(ctx, size) }
                    .frame(height: 260)
                    .accessibilityLabel("A jármű napi nyomvonala")
                FlowLayout(spacing: 16, lineSpacing: 4) {
                    legend(line: Theme.primary, "gyors")
                    legend(line: Theme.late.opacity(0.7), "lassú vagy áll")
                    HStack(spacing: 6) {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 1))
                            p.addLine(to: CGPoint(x: 16, y: 1))
                        }
                        .stroke(Theme.mutedForeground.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: 16, height: 2)
                        Text("adathiány")
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Theme.ontime).frame(width: 8, height: 8)
                        Text("nap eleje")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.mutedForeground)
            }
        }
    }

    private func legend(line: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(line).frame(width: 16, height: 2)
            Text(text)
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let pad = 12.0
        let w = max(size.width, 240)
        let h = size.height
        let lats = track.map(\.lat)
        let lons = track.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        let kx = cos((minLat + maxLat) / 2 * .pi / 180)
        let spanX = max((maxLon - minLon) * kx, 1e-6)
        let spanY = max(maxLat - minLat, 1e-6)
        let scale = min((w - pad * 2) / spanX, (h - pad * 2) / spanY)
        let offX = (w - spanX * scale) / 2
        let offY = (h - spanY * scale) / 2
        func point(_ p: StatsTrackPoint) -> CGPoint {
            CGPoint(x: offX + (p.lon - minLon) * kx * scale, y: h - offY - (p.lat - minLat) * scale)
        }

        for i in 1..<track.count {
            let prev = track[i - 1]
            let p = track[i]
            let speed = p.speed ?? 0
            let isGap = (p.t - prev.t) / 60 > 5
            var path = Path()
            path.move(to: point(prev))
            path.addLine(to: point(p))
            let color: Color = isGap ? Theme.mutedForeground.opacity(0.4) : speed >= Self.fastDms ? Theme.primary : speed > 10 ? Theme.primary.opacity(0.6) : Theme.late.opacity(0.7)
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: isGap ? 1 : 2, lineCap: .round, dash: isGap ? [3, 4] : []))
        }

        for (p, color) in [(track[0], Theme.ontime), (track[track.count - 1], Theme.late)] {
            let c = point(p)
            let rect = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: rect), with: .color(color))
            ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.card), lineWidth: 2)
        }
    }
}
