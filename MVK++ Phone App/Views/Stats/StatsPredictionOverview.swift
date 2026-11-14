//
//  StatsPredictionOverview.swift
//  MVK++ Phone App
//

import SwiftUI

/// Rendszám-jóslás (web `PredictionOverview.tsx`): which bus will run a trip
/// not yet departed — the tips given 30, 15 and 5 minutes before, as they
/// turned out when the trip left.
struct StatsPredictionOverview: View {
    private static let ranges: [StatsPillItem<String>] = [
        .init(id: "1", label: "Ma"),
        .init(id: "7", label: "7 nap"),
        .init(id: "14", label: "14 nap"),
        .init(id: "30", label: "30 nap"),
    ]

    private static let signals: [String: (label: String, sub: String)] = [
        "chain": ("Forda-lánc", "aki az előző menetet vitte, megy tovább"),
        "turnaround": ("Forda-terv", "a kint lévő buszok órákra előre végigvezetve"),
        "terminal": ("Végállomáson vár", "a menet indulási pontján álló busz"),
        "slot": ("Megszokás", "ki szokta vinni ezt a menetet ilyen napon"),
    ]

    @StateObject private var query = StatsQuery<StatsPredictionData>()
    @State private var range = "14"
    @State private var tripQuery = ""

    var body: some View {
        let to = StatsFormat.serviceToday()
        let from = StatsFormat.shiftDate(to, -((Int(range) ?? 14) - 1))
        let key = "\(from)|\(to)"

        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        StatsHeading("Rendszám-jóslás")
                        Text("Melyik busz viszi a még el nem indult menetet: a 30, 15 és 5 perccel előtte adott tippek, ahogy a menet indulásakor kiderült.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        StatsPillPicker(items: Self.ranges, value: range, onChange: { range = $0 }, groupLabel: "Időszak")
                        Button(action: query.reload) {
                            Image(systemName: "arrow.clockwise")
                                .symbolEffect(.rotate, isActive: query.loading)
                        }
                        .buttonStyle(StatsButtonStyle(icon: true))
                        .disabled(query.loading)
                        .accessibilityLabel("Frissítés")
                    }
                }

                StatsQueryBoundary(query) { d in
                    content(d, proxy: proxy)
                }
            }
        }
        .task(id: query.taskId(key)) {
            await query.run(key: key) { try await APIClient.shared.statsPredictions(from: from, to: to) }
        }
    }

    // MARK: - Grading

    fileprivate static func pct(n: Int, hits: Int) -> Int? {
        n > 0 ? Int((100 * Double(hits) / Double(n)).rounded()) : nil
    }

    fileprivate enum Grade { case good, fair, poor, none }

    fileprivate static func grade(_ p: Int?) -> Grade {
        guard let p else { return .none }
        return p >= 85 ? .good : p >= 65 ? .fair : .poor
    }

    fileprivate static func fill(_ g: Grade) -> Color {
        switch g {
        case .good: return Theme.ontime
        case .fair: return Theme.nosignal
        case .poor: return Theme.late
        case .none: return Theme.muted
        }
    }

    fileprivate static func tone(_ g: Grade) -> StatsTone {
        switch g {
        case .good: return .ontime
        case .poor: return .late
        case .fair, .none: return .standard
        }
    }

    fileprivate static func pctLabel(_ p: Int?) -> String { p.map { "\($0)%" } ?? "" }

    // MARK: - Content

    @ViewBuilder
    private func content(_ d: StatsPredictionData, proxy: ScrollViewProxy) -> some View {
        let total = d.byHorizon.reduce((n: 0, hits: 0)) { ($0.n + $1.n, $0.hits + $1.hits) }
        if total.n == 0 {
            StatsEmptyChart(text: "Ebben az időszakban még nincs kiértékelt jóslat.\(d.pendingToday > 0 ? " Ma \(StatsFormat.number(d.pendingToday)) tipp vár a menet indulására." : "")")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                summary(d, total: total)
                calibration(d)
                StatsChartFrame(title: "Napi találati arány", hint: "Minden kiértékelt tipp, horizonttól függetlenül.") {
                    StatsLineChart(
                        data: d.daily.map { StatsLinePoint(label: String($0.date.dropFirst(5)).replacingOccurrences(of: "-", with: "."), value: Self.pct(n: $0.n, hits: $0.hits).map(Double.init)) },
                        unit: "%"
                    )
                }
                StatsChartFrame(title: "Napszak szerint", hint: "A menet menetrendi indulásának órája.") {
                    StatsBarChart(
                        data: d.byHour.map { x in
                            let p = Self.pct(n: x.n, hits: x.hits)
                            return StatsBarDatum(
                                label: StatsFormat.serviceHour(x.hour),
                                value: p.map(Double.init),
                                tone: Self.fill(Self.grade(p)),
                                title: "\(Self.pctLabel(p)) talált · \(StatsFormat.serviceHour(x.hour)) órakor · \(StatsFormat.number(x.n)) tipp"
                            )
                        },
                        unit: "%",
                        maxValue: 100
                    )
                }
                signals(d)
                routes(d)
                vehicles(d) { id in
                    tripQuery = id
                    withAnimation(Theme.Motion.normalAnimation) { proxy.scrollTo("prediction-trips", anchor: .top) }
                }
                StatsChartFrame(title: "Tippek menetenként", hint: "A legutóbbi \(StatsFormat.number(d.trips.count)) kiértékelt menet. Az áthúzott rendszám a téves tipp.") {
                    StatsPredictionTripList(trips: d.trips, query: $tripQuery, multiDay: range != "1")
                }
                .id("prediction-trips")
            }
        }
    }

    private func summary(_ d: StatsPredictionData, total: (n: Int, hits: Int)) -> some View {
        let all = Self.pct(n: total.n, hits: total.hits)
        return StatsTileGrid {
            StatsStatTile(label: "Összes találat", value: Self.pctLabel(all), sub: "\(StatsFormat.number(total.hits)) / \(StatsFormat.number(total.n)) tipp", tone: Self.tone(Self.grade(all)))
            ForEach([30, 15, 5], id: \.self) { h in
                let row = d.byHorizon.first { $0.horizon == h }
                let p = row.flatMap { Self.pct(n: $0.n, hits: $0.hits) }
                StatsStatTile(
                    label: "\(h) perccel előtte",
                    value: Self.pctLabel(p),
                    sub: row.map { "\(StatsFormat.number($0.hits)) / \(StatsFormat.number($0.n)) · átl. \(Int(($0.avg_conf * 100).rounded()))%-ot ígért" } ?? "nincs tipp",
                    tone: Self.tone(Self.grade(p))
                )
            }
            StatsStatTile(label: "Ma még nyitott", value: StatsFormat.number(d.pendingToday), sub: "tipp vár a menet indulására")
        }
    }

    /// Calibration: when it says X%, does it hit X% of the time?
    private func calibration(_ d: StatsPredictionData) -> some View {
        let n = d.calibration.reduce(0) { $0 + $1.n }
        let gap = n > 0 ? Int((d.calibration.reduce(0.0) { $0 + (Double($1.hits) - $1.avg_conf * Double($1.n)) } / Double(n) * 100).rounded()) : 0
        let verdict = abs(gap) <= 3
            ? "A bizonyosság pontosan azt jelenti, amit mond."
            : gap > 0
                ? "Szerényebb a valóságnál: átlagosan \(gap) százalékponttal többször talál, mint amit ígér."
                : "Túl magabiztos: átlagosan \(-gap) százalékponttal ritkábban talál, mint amit ígér."
        return StatsChartFrame(title: "Mennyit ér a bizonyosság?", hint: "Bizonyosság-sávonként a tényleges találati arány. A 80%-os tippnek kb. 80%-ban kell bejönnie.") {
            VStack(alignment: .leading, spacing: 8) {
                StatsBarChart(
                    data: d.calibration.map { b in
                        let p = Self.pct(n: b.n, hits: b.hits)
                        let honest = p.map { Double($0) >= b.avg_conf * 100 - 5 } ?? false
                        return StatsBarDatum(
                            label: "\(b.bucket * 10)%",
                            value: p.map(Double.init),
                            tone: honest ? Theme.ontime : Theme.late,
                            title: "\(Self.pctLabel(p)) talált · \(b.bucket * 10)–\(b.bucket * 10 + 10)%-os tippeknél (átl. \(Int((b.avg_conf * 100).rounded()))%) · \(StatsFormat.number(b.n)) tipp"
                        )
                    },
                    unit: "%",
                    maxValue: 100
                )
                let strong = Text(verdict).fontWeight(.medium).foregroundStyle(Theme.foreground)
                Text("\(strong) Zöld: legalább annyit talál, amennyit ígér; piros: kevesebbet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func signals(_ d: StatsPredictionData) -> some View {
        let ranked = d.signals.sorted { (Self.pct(n: $0.n, hits: $0.hits) ?? 0) > (Self.pct(n: $1.n, hits: $1.hits) ?? 0) }
        let rows = ranked.map { s -> StatsRankRow in
            let alone = Self.pct(n: s.n, hits: s.hits)
            let decided = d.byMethod.first { $0.method == s.signal }
            let w = d.weights.first { $0.signal == s.signal }
            let meta = Self.signals[s.signal] ?? (s.signal, "")
            let parts = [
                "egyedül \(StatsFormat.number(s.hits))/\(StatsFormat.number(s.n))",
                decided.map { "döntött \(StatsFormat.number($0.n))× (\(Self.pctLabel(Self.pct(n: $0.n, hits: $0.hits))))" },
                w.map { "tanult súly \(String(format: "%.2f", $0.weight).replacingOccurrences(of: ".", with: ","))" },
            ].compactMap { $0 }
            return StatsRankRow(
                label: meta.label,
                sub: "\(meta.sub) · \(parts.joined(separator: " · "))",
                value: Double(alone ?? 0),
                display: Self.pctLabel(alone),
                bar: Self.fill(Self.grade(alone)).opacity(Self.grade(alone) == .none ? 1 : 0.8)
            )
        }
        return StatsChartFrame(title: "Melyik jelzés mennyire pontos", hint: "Ha csak ez a jelzés döntött volna, milyen arányban lett volna igaza.") {
            StatsRankBars(rows: rows)
        }
    }

    private func routes(_ d: StatsPredictionData) -> some View {
        let top = Array(d.byRoute.prefix(16))
        return StatsChartFrame(title: "Vonalanként", hint: "A \(top.count) legtöbbet tippelt vonal (összesen \(d.byRoute.count)).") {
            if top.isEmpty {
                StatsEmptyChart()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(top, id: \.route_short) { r in
                        let p = Self.pct(n: r.n, hits: r.hits)
                        VStack(spacing: 4) {
                            HStack(spacing: 10) {
                                StatsRoutePill(route: r.route_short, color: r.color, text: r.text_color)
                                    .frame(width: 36, alignment: .leading)
                                Text("\(StatsFormat.number(r.hits)) / \(StatsFormat.number(r.n)) tipp")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(Self.pctLabel(p))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .monospacedDigit()
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.muted)
                                    Capsule().fill(Self.fill(Self.grade(p)).opacity(0.8))
                                        .frame(width: geo.size.width * Double(p ?? 0) / 100)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    private func vehicles(_ d: StatsPredictionData, onPick: @escaping (String) -> Void) -> some View {
        let carried = d.byVehicle.filter { $0.n > 0 }
        let onlyWrong = d.byVehicle.filter { $0.n == 0 }
        let perfect = carried.filter { $0.hits == $0.n }.count
        return StatsChartFrame(title: "Rendszámok", hint: "\(StatsFormat.number(carried.count)) busz menetét tippeltük; \(StatsFormat.number(perfect)) esetében minden tipp talált. Kattints egyre a menetei listájáért.") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
                    ForEach(carried, id: \.vehicle_id) { v in
                        let g = Self.grade(Self.pct(n: v.n, hits: v.hits))
                        Button {
                            onPick(v.vehicle_id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(v.vehicle_id)
                                    .font(Theme.mono(12.5, weight: .bold))
                                    .foregroundStyle(Theme.foreground)
                                let wrong = Text(" · \(v.wrong_picks)× tévesen").foregroundStyle(Theme.late)
                                Group {
                                    if v.wrong_picks > 0 {
                                        Text("\(v.hits)/\(v.n)\(wrong)")
                                    } else {
                                        Text("\(v.hits)/\(v.n)")
                                    }
                                }
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(Theme.mutedForeground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(g == .none ? Theme.card : chipTint(g).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(g == .none ? Theme.border : chipTint(g).opacity(0.4), lineWidth: 1)
                                if tripQueryActive(v.vehicle_id) {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Theme.foreground.opacity(0.6), lineWidth: 2)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(v.vehicle_id): \(v.n) menetéből \(v.hits)-t eltaláltunk\(v.wrong_picks > 0 ? ", \(v.wrong_picks)× tévesen tippeltük rá más menetére" : "")")
                    }
                }
                if !onlyWrong.isEmpty {
                    Text("Csak téves tippben szerepelt: \(onlyWrong.map { "\($0.vehicle_id) (\($0.wrong_picks)×)" }.joined(separator: ", "))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tripQueryActive(_ id: String) -> Bool { tripQuery == id }

    private func chipTint(_ g: Grade) -> Color {
        g == .none ? Theme.card : Self.fill(g)
    }
}

/// Per trip: what we predicted 30 / 15 / 5 minutes before, and who actually
/// ran it (web `PredictionTripList.tsx`).
struct StatsPredictionTripList: View {
    let trips: [StatsPredictionTrip]
    @Binding var query: String
    let multiDay: Bool

    private enum Verdict: String { case all, hit, mixed, miss }
    private static let page = 60

    @State private var verdict: Verdict = .all
    @State private var shown = page

    static func hm(_ sec: Int) -> String {
        "\((sec / 3600) % 24):\(String(format: "%02d", (sec % 3600) / 60))"
    }

    private func verdictOf(_ t: StatsPredictionTrip) -> Verdict {
        let hits = t.guesses.filter(\.ok).count
        return hits == t.guesses.count ? .hit : hits == 0 ? .miss : .mixed
    }

    var body: some View {
        let searched = search()
        let counts = (all: searched.count,
                      hit: searched.filter { verdictOf($0) == .hit }.count,
                      mixed: searched.filter { verdictOf($0) == .mixed }.count,
                      miss: searched.filter { verdictOf($0) == .miss }.count)
        let rows = verdict == .all ? searched : searched.filter { verdictOf($0) == verdict }

        VStack(alignment: .leading, spacing: 12) {
            // Only typing starts the list over; a plate picked above keeps it.
            StatsSearchField(
                text: Binding(get: { query }, set: { query = $0; shown = Self.page }),
                placeholder: "Rendszám, vonal vagy cél",
                fieldLabel: "Jóslatok szűrése rendszámra, vonalra vagy célállomásra"
            )
            StatsPillPicker(
                items: [
                    .init(id: Verdict.all, label: "Mind", sub: String(counts.all)),
                    .init(id: .hit, label: "Talált", sub: String(counts.hit)),
                    .init(id: .mixed, label: "Részben", sub: String(counts.mixed)),
                    .init(id: .miss, label: "Tévedett", sub: String(counts.miss)),
                ],
                value: verdict,
                onChange: {
                    verdict = $0
                    shown = Self.page
                },
                groupLabel: "Kimenetel szerint"
            )

            if rows.isEmpty {
                StatsEmptyChart(text: query.isEmpty ? "Ebben az időszakban nincs ilyen jóslat." : "Nincs „\(query)” jóslat ebben az időszakban.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(shown).enumerated()), id: \.element.id) { i, t in
                        if i > 0 { Divider().overlay(Theme.border) }
                        row(t)
                    }
                }
                .statsCard(radius: 12, fill: .clear)
            }

            if rows.count > shown {
                Button {
                    shown += Self.page
                } label: {
                    Text("További \(min(Self.page, rows.count - shown)) menet (\(rows.count - shown) van még)")
                }
                .buttonStyle(StatsButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func row(_ t: StatsPredictionTrip) -> some View {
        let v = verdictOf(t)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.hm(t.sched_start_s))
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                if multiDay {
                    Text("\(String(t.date.dropFirst(5)).replacingOccurrences(of: "-", with: ".")).")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatsRoutePill(route: t.route_short, color: t.color, text: t.text_color)
                    Text(t.headsign ?? "")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                }
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(t.guesses, id: \.self) { g in guessChip(g) }
                    let actual = Text(t.actual).font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.foreground)
                    Text("vitte: \(actual)")
                        .font(.system(size: 11))
                        .foregroundStyle(v == .hit ? Theme.ontime : v == .miss ? Theme.late : Theme.mutedForeground)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func guessChip(_ g: StatsPredictionGuess) -> some View {
        HStack(spacing: 4) {
            Image(systemName: g.ok ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(g.ok ? Theme.ontime : Theme.late)
            Text("\(g.h)′").foregroundStyle(Theme.mutedForeground)
            Text(g.v)
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .strikethrough(!g.ok, color: Theme.late.opacity(0.6))
            Text("\(Int((g.c * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(Theme.mutedForeground)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((g.ok ? Theme.ontime : Theme.late).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder((g.ok ? Theme.ontime : Theme.late).opacity(0.35), lineWidth: 1))
        .accessibilityLabel("\(g.h) perccel indulás előtt: \(g.v) (\(Int((g.c * 100).rounded()))% bizonyosság) \(g.ok ? "talált" : "tévedett")")
    }

    private func search() -> [StatsPredictionTrip] {
        let q = query.trimmingCharacters(in: .whitespaces).normalizedForSearch
        guard !q.isEmpty else { return trips }
        return trips.filter {
            $0.actual.contains(q)
                || $0.guesses.contains { $0.v.contains(q) }
                || $0.route_short.normalizedForSearch == q
                || ($0.headsign ?? "").normalizedForSearch.contains(q)
        }
    }
}
