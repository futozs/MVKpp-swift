//
//  StatsHeatPanel.swift
//  MVK++ Phone App
//

import MapKit
import SwiftUI

/// Hőtérkép (web `HeatPanel.tsx`): where and when the buses run late.
///  · Vonal — one route's stops × the hours of the day
///  · Város — the whole network's stop-to-stop links on the map, played hour by hour
struct StatsHeatPanel: View {
    let routes: [Route]

    @ObservedObject private var local = LocalStore.shared
    @StateObject private var routeQ = StatsQuery<StatsRouteHeat>()
    @StateObject private var cityQ = StatsQuery<StatsCityHeat>()

    @State private var view = "route"
    @State private var daytype = "0"
    @State private var days = "28"
    @State private var dir: String?

    /// Device-only on the web (`mvk_heat_route` is not synced), raw string.
    private static let routeKey = "mvk_heat_route"

    private static let daytypes: [StatsPillItem<String>] = [
        .init(id: "0", label: "Munkanap"),
        .init(id: "1", label: "Szombat"),
        .init(id: "2", label: "Vasárnap, ünnep"),
    ]

    private static let ranges: [StatsPillItem<String>] = [
        .init(id: "14", label: "14 nap"),
        .init(id: "28", label: "4 hét"),
        .init(id: "60", label: "2 hónap"),
    ]

    private var route: String? {
        local.string(Self.routeKey) ?? (routes.first { $0.short == "14" } ?? routes.first)?.short
    }

    private func pickRoute(_ short: String) {
        dir = nil
        local.set(Self.routeKey, short)
    }

    var body: some View {
        let routeKey = "\(route ?? "")|\(dir ?? "")|\(days)|\(daytype)"
        let cityKey = "\(days)|\(daytype)"

        VStack(alignment: .leading, spacing: 16) {
            header

            if view == "route" {
                StatsSearchablePicker(
                    items: routes.map { StatsPillItem(id: $0.short, label: $0.short, sub: $0.long, color: $0.color) },
                    value: route,
                    onChange: pickRoute,
                    placeholder: "Vonal keresése",
                    limit: 80,
                    groupLabel: "Vonal"
                )
                routeFrame
            } else {
                StatsChartFrame(title: "Városi hőtérkép", hint: "megállóközönként: mennyi időt veszít a busz a menetrendhez képest") {
                    StatsQueryBoundary(cityQ, empty: { $0.segments.isEmpty }) { d in
                        StatsCityHeatMap(data: d)
                    }
                }
            }
        }
        .task(id: routeQ.taskId(routeKey, enabled: view == "route" && route != nil)) {
            let r = route ?? ""
            let d = dir
            let n = Int(days) ?? 28
            let t = Int(daytype) ?? 0
            await routeQ.run(key: routeKey, enabled: view == "route" && route != nil) {
                try await APIClient.shared.routeHeat(route: r, dir: d, days: n, daytype: t)
            }
        }
        .task(id: cityQ.taskId(cityKey, enabled: view == "city")) {
            let n = Int(days) ?? 28
            let t = Int(daytype) ?? 0
            await cityQ.run(key: cityKey, enabled: view == "city") { try await APIClient.shared.cityHeat(days: n, daytype: t) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    StatsHeading("Hőtérkép")
                    Text("Hol és mikor késnek a buszok, a lezárt napok mért megálló-időiből, mediánnal (egy-egy kiugró menet nem torzít).")
                        .font(Theme.sans(12.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            StatsSegmented(options: [("route", "Vonal"), ("city", "Város")], selection: $view, large: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Nézet")
            StatsPillPicker(items: Self.daytypes, value: daytype, onChange: { daytype = $0 }, groupLabel: "Naptípus")
            StatsPillPicker(items: Self.ranges, value: days, onChange: { days = $0 }, groupLabel: "Időszak")
        }
    }

    private var routeFrame: some View {
        let data = routeQ.data.flatMap { $0.route == route ? $0 : nil }
        let title = data.map { d in "\(d.route) \(d.directions.first { $0.dir == d.dir }?.headsign ?? "")" } ?? "Vonal-hőtérkép"
        return StatsChartFrame(title: title, hint: "megállók menetirányban × a nap órái") {
            if let data, data.directions.count > 1 {
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(data.directions, id: \.dir) { d in
                        let on = d.dir == data.dir
                        Button {
                            dir = d.dir
                        } label: {
                            Text(d.headsign)
                                .font(Theme.sans(11.5, weight: .semibold))
                                .lineLimit(1)
                                .frame(maxWidth: 200)
                                .fixedSize()
                                .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(on ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(on ? Theme.primary : Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        } content: {
            StatsQueryBoundary(routeQ, empty: { $0.cells.isEmpty }) { _ in
                if let data { StatsRouteHeatView(data: data) }
            }
        }
    }
}

/// A rounded segmented control (`role="tablist"` / `radiogroup` on the web).
struct StatsSegmented<ID: Hashable>: View {
    let options: [(ID, String)]
    @Binding var selection: ID
    var large = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { id, label in
                let on = selection == id
                Button {
                    selection = id
                } label: {
                    Text(label)
                        .font(Theme.sans(large ? 14 : 12, weight: .semibold))
                        .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                        .padding(.horizontal, large ? 16 : 10)
                        .padding(.vertical, large ? 6 : 4)
                        .background(on ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: large ? 12 : 10, style: .continuous))
                        .mvkShadow(on ? Theme.Shadow.sm : Theme.Shadow.Level(radius: 0, y: 0, opacity: 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(large ? 4 : 2)
        .background(Theme.muted.opacity(0.4), in: RoundedRectangle(cornerRadius: large ? 16 : 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: large ? 16 : 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

// MARK: - Scale

/// The heat maps' diverging scale (`heatScale.ts`): early blue → on time
/// green → yellow → orange → red, ending on the theme's meaning colours.
enum StatsHeatScale {
    enum Metric { case delay, gain, loss }

    private static let delayStops: [(Double, [Double])] = [
        (-180, [208, 83, 62]), (-30, [170, 45, 34]), (45, [153, 52, 40]), (120, [52, 88, 52]),
        (240, [30, 92, 54]), (420, [9, 86, 56]), (720, [0, 82, 40]),
    ]

    /// Time lost on a link (s): green around 0, red above 2 minutes.
    private static let lossStops: [(Double, [Double])] = [
        (-45, [208, 83, 62]), (0, [153, 52, 40]), (25, [70, 70, 46]), (50, [45, 90, 52]),
        (90, [25, 92, 54]), (150, [9, 86, 56]), (240, [0, 82, 40]),
    ]

    static let legend: [Metric: [Double]] = [
        .delay: [-120, 0, 60, 180, 300, 600],
        .gain: [-30, 0, 30, 60, 120, 210],
        .loss: [-30, 0, 30, 60, 120, 210],
    ]

    static func color(_ metric: Metric, _ sec: Double, alpha: Double = 1) -> Color {
        let stops = metric == .delay ? delayStops : lossStops
        let hsl = lerp(stops, sec)
        return hslColor(hsl[0], hsl[1], hsl[2]).opacity(alpha)
    }

    private static func lerp(_ stops: [(Double, [Double])], _ v: Double) -> [Double] {
        guard let first = stops.first, let last = stops.last else { return [0, 0, 0] }
        if v <= first.0 { return first.1 }
        for i in 1..<stops.count {
            let (x1, c1) = stops[i]
            if v > x1 { continue }
            let (x0, c0) = stops[i - 1]
            let t = (v - x0) / (x1 - x0)
            return (0..<3).map { c0[$0] + (c1[$0] - c0[$0]) * t }
        }
        return last.1
    }

    private static func hslColor(_ h: Double, _ s: Double, _ l: Double) -> Color {
        let s = s / 100
        let l = l / 100
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let rgb: (Double, Double, Double)
        switch h {
        case 0..<60: rgb = (c, x, 0)
        case 60..<120: rgb = (x, c, 0)
        case 120..<180: rgb = (0, c, x)
        case 180..<240: rgb = (0, x, c)
        case 240..<300: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        return Color(red: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m)
    }

    /// ±m:ss; on time (±30 s) is "±0".
    static func fmtSec(_ sec: Double?) -> String {
        guard let sec else { return "" }
        if abs(sec) < 30 { return "±0" }
        let a = Int(abs(sec).rounded())
        return "\(sec > 0 ? "+" : "−")\(a / 60):\(String(format: "%02d", a % 60))"
    }

    static func hourLabel(_ h: Int) -> String {
        String(format: "%02d–%02d", h % 24, (h + 1) % 24)
    }
}

struct StatsHeatLegend: View {
    let metric: StatsHeatScale.Metric

    var body: some View {
        let steps = StatsHeatScale.legend[metric] ?? []
        let top = Int(((steps.last ?? 0) / 60).rounded())
        HStack(spacing: 6) {
            Text(metric == .delay ? "korán" : "behoz")
            HStack(spacing: 0) {
                ForEach(steps, id: \.self) { s in
                    StatsHeatScale.color(metric, s).frame(width: 20)
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            Text(metric == .delay ? "\(top)+ perc késés" : "\(top)+ perc veszteség")
        }
        .font(Theme.sans(10))
        .foregroundStyle(Theme.mutedForeground)
        .accessibilityHidden(true)
    }
}

// MARK: - Route heat

/// One route's stops (top to bottom, in travel order) × the hours of the
/// day. "Késés": how late the bus is there; "Hol szedi fel": how much its
/// delay grew since the previous stop — which link is to blame.
struct StatsRouteHeatView: View {
    let data: StatsRouteHeat

    private enum Metric: Hashable { case delay, gain }
    /// Fewer samples than this and the cell is faded (little data).
    private static let solidN = 8

    @State private var metric: Metric = .delay
    @State private var sel: (stop: Int, h: Int)?

    private struct Key: Hashable { let stop: Int; let h: Int }

    var body: some View {
        let grid = Dictionary(data.cells.map { (Key(stop: $0.stop, h: $0.h), $0) }, uniquingKeysWith: { first, _ in first })
        let hours = Array(data.hours.from...max(data.hours.from, data.hours.to))
        let solid = data.cells.filter { $0.n >= Self.solidN }
        let worst = solid.max { $0.p50 < $1.p50 }
        let gainer = solid.filter { $0.gain != nil && $0.stop > 0 }.max { ($0.gain ?? 0) < ($1.gain ?? 0) }
        let bestHour = bestHour(solid)
        let selected = sel.flatMap { grid[Key(stop: $0.stop, h: $0.h)] }

        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                if let worst {
                    insight(icon: "flame", tone: Theme.late, title: "Itt késik a legtöbbet") {
                        let v = Text(StatsHeatScale.fmtSec(worst.p50)).font(Theme.mono(12.5, weight: .bold))
                        return Text("\(stopName(worst.stop)), \(StatsHeatScale.hourLabel(worst.h)) óra: \(v) (medián)")
                    }
                }
                if let gainer, (gainer.gain ?? 0) >= 30 {
                    insight(icon: "tortoise", tone: Theme.late, title: "Itt szedi fel a késést") {
                        let v = Text(StatsHeatScale.fmtSec(gainer.gain)).font(Theme.mono(12.5, weight: .bold))
                        return Text("\(stopName(gainer.stop - 1)) → \(stopName(gainer.stop)), \(StatsHeatScale.hourLabel(gainer.h)): \(v)")
                    }
                }
                if let bestHour {
                    insight(icon: "sparkles", tone: Theme.ontime, title: "A legpontosabb napszak") {
                        let v = Text(StatsHeatScale.fmtSec(bestHour.avg)).font(Theme.mono(12.5, weight: .bold))
                        return Text("\(StatsHeatScale.hourLabel(bestHour.h)) óra: átlagosan \(v) eltérés")
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    metricToggle
                    Spacer(minLength: 0)
                    StatsHeatLegend(metric: metric == .delay ? .delay : .gain)
                }
                VStack(alignment: .leading, spacing: 8) {
                    metricToggle
                    StatsHeatLegend(metric: metric == .delay ? .delay : .gain)
                }
            }

            gridView(grid: grid, hours: hours)

            Group {
                if let s = selected {
                    let p50 = Text(StatsHeatScale.fmtSec(s.p50)).font(Theme.mono(12, weight: .bold)).foregroundStyle(Theme.foreground)
                    let p85 = Text(StatsHeatScale.fmtSec(s.p85)).font(Theme.mono(12, weight: .bold)).foregroundStyle(Theme.foreground)
                    let name = Text(stopName(s.stop)).fontWeight(.semibold).foregroundStyle(Theme.foreground)
                    if let g = s.gain, s.stop > 0 {
                        let gain = Text(StatsHeatScale.fmtSec(g)).font(Theme.mono(12, weight: .bold)).foregroundStyle(Theme.foreground)
                        Text("\(name), \(StatsHeatScale.hourLabel(s.h)) óra · medián \(p50), a buszok 85%-a legfeljebb \(p85) · az előző megálló óta \(gain) · \(s.n) áthaladás \(data.days) napból")
                    } else {
                        Text("\(name), \(StatsHeatScale.hourLabel(s.h)) óra · medián \(p50), a buszok 85%-a legfeljebb \(p85) · \(s.n) áthaladás \(data.days) napból")
                    }
                } else {
                    Text("Koppints egy cellára a részletekért. Fentről lefelé menetirányban haladnak a megállók; a halvány cella kevés mérésből jön.")
                }
            }
            .font(Theme.sans(12))
            .foregroundStyle(Theme.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.muted.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
    }

    private var metricToggle: some View {
        StatsSegmented(options: [(Metric.delay, "Késés a megállóban"), (.gain, "Hol szedi fel")], selection: $metric)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mit mutasson")
    }

    private func stopName(_ i: Int) -> String {
        data.stops[statsSafe: i]?.name ?? ""
    }

    private func bestHour(_ solid: [StatsRouteHeat.Cell]) -> (h: Int, avg: Double)? {
        var byH: [Int: (s: Double, n: Int)] = [:]
        var order: [Int] = []
        for c in solid {
            if byH[c.h] == nil { order.append(c.h) }
            let cur = byH[c.h] ?? (0, 0)
            byH[c.h] = (cur.s + abs(c.p50) * Double(c.n), cur.n + c.n)
        }
        // A tie goes to the hour met first, as the web's stable sort does.
        var best: (h: Int, avg: Double)?
        for h in order {
            guard let v = byH[h], v.n >= 40 else { continue }
            let avg = v.s / Double(v.n)
            if best == nil || avg < (best?.avg ?? 0) { best = (h, avg) }
        }
        return best.map { ($0.h, $0.avg.rounded()) }
    }

    private func insight(icon: String, tone: Color, title: String, text: () -> Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title.uppercased())
                    .font(Theme.sans(10.5, weight: .semibold))
                    .tracking(0.5)
            }
            .foregroundStyle(tone)
            text()
                .font(Theme.sans(12.5))
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsCard(radius: 16, fill: Theme.background.opacity(0.5))
    }

    private func gridView(grid: [Key: StatsRouteHeat.Cell], hours: [Int]) -> some View {
        GeometryReader { geo in
            let labelW = max(84, geo.size.width * 0.3)
            let cellW = (geo.size.width - labelW - CGFloat(hours.count)) / CGFloat(max(1, hours.count))
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    Theme.card.frame(width: labelW, height: 16)
                    ForEach(hours, id: \.self) { h in
                        Text(h % 3 == 0 ? String(format: "%02d", h % 24) : "")
                            .font(Theme.mono(9, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: cellW, height: 16)
                            .background(Theme.card)
                    }
                }
                ForEach(Array(data.stops.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 1) {
                        Text(s.name)
                            .font(Theme.sans(10.5))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                            .padding(.leading, 8)
                            .padding(.trailing, 4)
                            .frame(width: labelW, height: 18, alignment: .leading)
                            .background(Theme.card)
                        ForEach(hours, id: \.self) { h in
                            cell(grid[Key(stop: i, h: h)], stop: i, h: h)
                                .frame(width: cellW, height: 18)
                        }
                    }
                }
            }
            .background(Theme.border)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .frame(height: CGFloat(data.stops.count) * 19 + 17)
        .accessibilityLabel("\(data.route) vonal hőtérképe")
    }

    @ViewBuilder
    private func cell(_ c: StatsRouteHeat.Cell?, stop: Int, h: Int) -> some View {
        let empty = c == nil || (metric == .gain && (c?.gain == nil || stop == 0))
        let on = sel?.stop == stop && sel?.h == h
        if let c, !empty {
            let value = metric == .delay ? c.p50 : (c.gain ?? 0)
            Rectangle()
                .fill(StatsHeatScale.color(metric == .delay ? .delay : .gain, value, alpha: c.n >= Self.solidN ? 1 : 0.55))
                .overlay { if on { Rectangle().strokeBorder(Theme.foreground, lineWidth: 2) } }
                .contentShape(Rectangle())
                .onTapGesture { sel = on ? nil : (stop, h) }
                .accessibilityLabel("\(stopName(stop)), \(StatsHeatScale.hourLabel(h)) óra: \(StatsHeatScale.fmtSec(value))")
        } else {
            Theme.muted.opacity(0.25)
                .accessibilityLabel("\(stopName(stop)), \(StatsHeatScale.hourLabel(h)) óra: nincs adat")
        }
    }
}

// MARK: - City heat

/// Every stop-to-stop link coloured by the time the bus loses there in the
/// chosen hour (median over the day type's recent weeks). The slider and
/// play button run through the day.
struct StatsCityHeatMap: View {
    let data: StatsCityHeat

    private static let center = CLLocationCoordinate2D(latitude: 48.1035, longitude: 20.7784)
    private static let playInterval: Duration = .milliseconds(1100)

    @State private var hour: Int?
    @State private var playing = false
    @State private var picked: StatsCityHeat.Segment?
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: StatsCityHeatMap.center,
        span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.07)
    ))

    private var currentHour: Int {
        hour ?? initialHour
    }

    private var initialHour: Int {
        let f = DateFormatter()
        f.timeZone = StatsFormat.budapest
        f.dateFormat = "H"
        let now = Int(f.string(from: Date(timeIntervalSince1970: RealtimeClient.shared.serverNow))) ?? 8
        return min(data.hours.to, max(data.hours.from, now))
    }

    private func weight(_ n: Int) -> CGFloat {
        let perHour = Double(n) / Double(max(1, data.days))
        return perHour >= 12 ? 6 : perHour >= 6 ? 5 : perHour >= 3 ? 4 : 3
    }

    var body: some View {
        let idx = currentHour - data.hours.from
        let live = data.segments
            .compactMap { s -> (StatsCityHeat.Segment, Double)? in
                guard let ex = s.ex[statsSafe: idx] ?? nil else { return nil }
                return (s, ex)
            }
            // The worst ones on top.
            .sorted { $0.1 < $1.1 }
        let top = Array(live.sorted { $0.1 > $1.1 }.prefix(5))
        let slow = live.filter { $0.1 >= 60 }.count

        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .top) {
                MapReader { proxy in
                    Map(position: $camera, interactionModes: [.pan, .zoom]) {
                        ForEach(live, id: \.0.id) { seg, ex in
                            MapPolyline(coordinates: seg.path.compactMap { p in
                                p.count >= 2 ? CLLocationCoordinate2D(latitude: p[0], longitude: p[1]) : nil
                            })
                            .stroke(StatsHeatScale.color(.loss, ex).opacity(0.92), style: StrokeStyle(lineWidth: weight(seg.n[statsSafe: idx] ?? 0), lineCap: .round, lineJoin: .round))
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .environment(\.colorScheme, .dark)
                    .onTapGesture { point in
                        // Every link is tappable, an hour without data included; only
                        // „Bezárás” closes the card.
                        if let hit = nearest(among: data.segments, proxy: proxy, tap: point) { picked = hit }
                    }
                }
                .containerRelativeFrame(.vertical) { height, _ in min(height * 0.62, 520) }
                .background(Theme.muted)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))

                Text("\(StatsHeatScale.hourLabel(currentHour)) óra")
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Theme.card.opacity(0.9), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                    .mvkShadow(Theme.Shadow.md)
                    .padding(.top, 8)
                    .allowsHitTesting(false)

                if let picked {
                    pickedCard(picked, idx: idx)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(8)
                }
            }

            HStack(spacing: 12) {
                Button {
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause" : "play")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.mvk(playing ? .primary : .outline, size: .icon))
                .accessibilityLabel(playing ? "Megállítás" : "A nap lejátszása")

                Slider(
                    value: Binding(
                        get: { Double(currentHour) },
                        set: {
                            playing = false
                            hour = Int($0.rounded())
                        }
                    ),
                    in: Double(data.hours.from)...Double(max(data.hours.from + 1, data.hours.to)),
                    step: 1
                )
                .tint(Theme.primary)
                .accessibilityLabel("Napszak")
                .accessibilityValue("\(StatsHeatScale.hourLabel(currentHour)) óra")
            }

            VStack(alignment: .leading, spacing: 6) {
                let slowText = Text("\(slow) szakaszon 1+ perc veszteség")
                    .fontWeight(slow > 0 ? .semibold : .regular)
                    .foregroundStyle(slow > 0 ? Theme.late : Theme.mutedForeground)
                Text("\(live.count) szakaszon van mérés · \(slowText)")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
                StatsHeatLegend(metric: .loss)
            }

            if !top.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.offset) { i, item in
                        if i > 0 { Divider().overlay(Theme.border.opacity(0.6)) }
                        Button {
                            picked = item.0
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(i + 1)")
                                    .font(Theme.mono(12, weight: .regular))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .frame(width: 16, alignment: .leading)
                                Circle().fill(StatsHeatScale.color(.loss, item.1)).frame(width: 12, height: 12)
                                Text("\(item.0.from) → \(item.0.to)")
                                    .font(Theme.sans(12.5))
                                    .foregroundStyle(Theme.foreground)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(StatsHeatScale.fmtSec(item.1))
                                    .font(Theme.mono(12, weight: .bold))
                                    .foregroundStyle(Theme.foreground)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .statsCard(radius: 16, fill: .clear)
            }
        }
        .task(id: playing) {
            guard playing else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.playInterval)
                guard !Task.isCancelled else { return }
                let h = currentHour
                hour = h >= data.hours.to ? data.hours.from : h + 1
            }
        }
    }

    private func pickedCard(_ s: StatsCityHeat.Segment, idx: Int) -> some View {
        let ex = s.ex[statsSafe: idx] ?? nil
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(s.from) → \(s.to)")
                .font(Theme.sans(12.5, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Group {
                if let ex {
                    let value = Text(StatsHeatScale.fmtSec(ex)).font(Theme.mono(12.5, weight: .bold)).foregroundStyle(Theme.foreground)
                    let sched = (s.sched[statsSafe: idx] ?? nil).flatMap { $0 != 0 ? $0 : nil }
                    let schedText = sched.map { " (menetrend \(String(StatsHeatScale.fmtSec($0).drop { "+−±".contains($0) })))" } ?? ""
                    Text("\(StatsHeatScale.hourLabel(currentHour)) óra: \(value) a menetrendhez képest\(schedText), \(s.n[statsSafe: idx] ?? 0) busz")
                } else {
                    Text("\(StatsHeatScale.hourLabel(currentHour)) óra: ebben az órában nincs mérés")
                }
            }
            .font(Theme.sans(12.5))
            .foregroundStyle(Theme.mutedForeground)
            Text("\(Int(s.m.rounded())) m · \(s.routes.joined(separator: ", "))")
                .font(Theme.sans(11))
                .foregroundStyle(Theme.mutedForeground)
            Button("Bezárás") { picked = nil }
                .font(Theme.sans(11, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .buttonStyle(.plain)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.opacity(0.95), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .mvkShadow(Theme.Shadow.lg)
    }

    /// The link closest to the tap, within a finger's width on screen.
    private func nearest(among segments: [StatsCityHeat.Segment], proxy: MapProxy, tap: CGPoint) -> StatsCityHeat.Segment? {
        var best: (StatsCityHeat.Segment, CGFloat)?
        for s in segments {
            let points = s.path.compactMap { p -> CGPoint? in
                guard p.count >= 2 else { return nil }
                return proxy.convert(CLLocationCoordinate2D(latitude: p[0], longitude: p[1]), to: .local)
            }
            guard points.count >= 2 else { continue }
            for i in 1..<points.count {
                let d = distance(tap, points[i - 1], points[i])
                if d < (best?.1 ?? 18) { best = (s, d) }
            }
        }
        return best?.0
    }

    private func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = dx * dx + dy * dy
        guard len > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
