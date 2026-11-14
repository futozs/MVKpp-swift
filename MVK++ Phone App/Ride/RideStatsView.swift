//
//  RideStatsView.swift
//  MVK++ Phone App
//
//  „Utazásaim” statistics: totals, the time delays took, collections and
//  records (web `RideStatsView`).
//

import Charts
import SwiftUI

struct RideStatsView: View {
    let stats: RideStats
    let fleetSize: Int?

    /// The hour tapped in „Mikor utazol” (web `BarChart` hover).
    @State private var selectedHour: Int?

    private static let weekdays = ["H", "K", "Sze", "Cs", "P", "Szo", "V"]
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.timeZone = ServiceClock.timeZone
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f
    }()

    var body: some View {
        let s = stats
        VStack(alignment: .leading, spacing: 16) {
            delayHero

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                RideStatTile(label: "Utazás", value: "\(s.journeys)", sub: s.loops > 0 ? "ebből \(s.loops) körbeutazás" : nil)
                RideStatTile(label: "Megtett út", value: "\(RideFormat.oneDecimal(s.km)) km", sub: "megállóról megállóra, légvonalban")
                RideStatTile(label: "Buszon töltött idő", value: RideFormat.minutes(s.minutes))
                RideStatTile(label: "Begyűjtött rendszám", value: "\(s.vehicles.count)", sub: fleetSize.map { "a flotta \($0) járművéből" }, tone: Theme.live)
                RideStatTile(label: "Begyűjtött megálló", value: "\(s.stopsCollected.count)", sub: "ahol fel- vagy leszálltál", tone: Theme.live)
                RideStatTile(
                    label: "Pontos busz",
                    value: s.onTimePct.map { "\($0)%" } ?? "—",
                    sub: "felszálláskor ±1 percen belül",
                    tone: (s.onTimePct ?? 0) >= 70 ? Theme.ontime : Theme.late
                )
            }

            RideChartFrame(title: "Hol szállsz fel", hint: "A felszállásaid helye") {
                RideRankBars(rows: s.boardStops.prefix(7).map { .init(label: $0.name, value: Double($0.n), display: "\($0.n)×") }, bar: Theme.primary.opacity(0.7))
            }
            RideChartFrame(title: "Hol szállsz le", hint: "A leszállásaid helye") {
                RideRankBars(rows: s.alightStops.prefix(7).map { .init(label: $0.name, value: Double($0.n), display: "\($0.n)×") }, bar: Theme.live.opacity(0.7))
            }
            RideChartFrame(title: "Leggyakoribb útjaid", hint: "Honnan hová") {
                RideRankBars(rows: s.pairs.prefix(7).map { .init(label: "\($0.from) → \($0.to)", value: Double($0.n), display: "\($0.n)×") }, bar: Theme.primary.opacity(0.45))
            }

            let busiest = s.hours.indices.max { s.hours[$0] < s.hours[$1] } ?? 0
            RideChartFrame(title: "Mikor utazol", hint: s.journeys > 0 ? "A legtöbbször \(busiest)–\(busiest + 1) óra között szállsz fel" : nil) {
                hoursChart
                weekdayBars.padding(.top, 16)
            }

            RideChartFrame(title: "Kedvenc vonalaid", hint: "Hányszor, és átlagosan mennyit késett felszálláskor") {
                VStack(spacing: 8) {
                    let top = s.routes.first?.n ?? 1
                    ForEach(s.routes.prefix(8)) { r in
                        HStack(spacing: 10) {
                            RouteTile(short: r.route, colorHex: r.color, textHex: r.text)
                                .frame(width: 48, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.muted)
                                    Capsule().fill(Theme.primary.opacity(0.7)).frame(width: proxy.size.width * CGFloat(r.n) / CGFloat(max(1, top)))
                                }
                            }
                            .frame(height: 8)
                            Text("\(r.n)×").font(Theme.mono(12, weight: .regular)).frame(width: 40, alignment: .trailing)
                            Text(r.avgDelayS.map(RideFormat.delayLabel) ?? "—")
                                .font(Theme.mono(11, weight: .regular))
                                .foregroundStyle(RideFormat.delayTone(r.avgDelayS))
                                .frame(width: 72, alignment: .trailing)
                        }
                        .monospacedDigit()
                    }
                }
            }

            RideChartFrame(title: "Rekordjaid") {
                VStack(spacing: 10) {
                    RideRecordCard(icon: "point.topleft.down.to.point.bottomright.curvepath", label: "Leghosszabb út", value: s.longest.map { "\(RideFormat.oneDecimal($0.value / 1000)) km" } ?? "—", legs: s.longest?.legs, day: Self.day)
                    RideRecordCard(icon: "timer", label: "Legtöbb plusz idő a buszon", value: s.mostDelayed.map { "+\(RideFormat.minutes(Int(($0.value / 60).rounded())))" } ?? "—", legs: s.mostDelayed?.legs, day: Self.day)
                    RideRecordCard(icon: "clock", label: "Leghosszabb ideig", value: s.longestTime.map { RideFormat.minutes(Int($0.value)) } ?? "—", legs: s.longestTime?.legs, day: Self.day)
                }
            }

            RideChartFrame(title: "Megállógyűjtemény", hint: "\(s.stopsCollected.count) megálló, ahol már fel- vagy leszálltál", icon: "mappin") {
                RideStopChips(stops: s.stopsCollected)
            }
            RideChartFrame(title: "Begyűjtött rendszámok", hint: "Melyik buszon hányszor utaztál", icon: "trophy") {
                FlowLayout(spacing: 6) {
                    ForEach(s.vehicles, id: \.0) { id, n in
                        RideChip {
                            Text(TransitIds.displayVehicleId(id)).font(Theme.mono(13, weight: .bold)).monospacedDigit()
                        } count: { n }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var delayHero: some View {
        let s = stats
        let total = s.extraOnboardS + s.lateWaitS
        let measured = "\(s.delayMeasured) / \(s.journeys) utadnál ismert a fel- és leszálláskori késés."
        let fmt = { (sec: Double) in RideFormat.minutes(Int((sec / 60).rounded())) }
        if total < 60 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Eddig nem vett el tőled időt a késés").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.foreground)
                Text(measured).font(.system(size: 12)).foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .rideCard()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                (Text(fmt(total)).fontWeight(.bold).foregroundColor(Theme.late) + Text(" ment el a késések miatt"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        if s.extraOnboardS > 0 { Rectangle().fill(Theme.late).frame(width: proxy.size.width * s.extraOnboardS / total) }
                        if s.lateWaitS > 0 { Rectangle().fill(Theme.late.opacity(0.4)) }
                    }
                }
                .frame(height: 8)
                .background(Theme.muted)
                .clipShape(Capsule())
                .padding(.top, 16)
                VStack(alignment: .leading, spacing: 16) {
                    delayPart(Theme.late, "A buszon ülve", fmt(s.extraOnboardS), "Ennyivel tartottak tovább az útjaid a menetrendnél.")
                    delayPart(Theme.late.opacity(0.4), "A megállóban várva", fmt(s.lateWaitS), "Ennyit vártál pluszban a késve érkező buszokra.")
                }
                .padding(.top, 16)
                Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1).padding(.top, 16)
                Text(measured).font(.system(size: 11.5)).foregroundStyle(Theme.mutedForeground).padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .rideCard()
        }
    }

    private func delayPart(_ swatch: Color, _ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(swatch).frame(width: 10, height: 10)
                Text(label).font(.system(size: 13)).foregroundStyle(Theme.mutedForeground)
            }
            Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.foreground).padding(.leading, 18)
            Text(note).font(.system(size: 12)).foregroundStyle(Theme.mutedForeground).padding(.leading, 18)
        }
    }

    private var hoursChart: some View {
        Chart {
            ForEach(Array(stats.hours.enumerated()), id: \.offset) { h, n in
                BarMark(x: .value("Óra", h), y: .value("Utazás", n), width: .ratio(0.75))
                    .foregroundStyle(Theme.primary.opacity(0.7))
                    .opacity(selectedHour == nil || selectedHour == h ? 1 : 0.4)
                    .cornerRadius(2)
                    .accessibilityLabel("\(h):00–\(h + 1):00")
                    .accessibilityValue("\(n) utazás")
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        if selectedHour == h {
                            StatsTip(value: "\(h):00–\(h + 1):00 · \(n) utazás")
                        }
                    }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { tap in
                            guard let plot = proxy.plotFrame else { return }
                            let x = tap.location.x - geometry[plot].origin.x
                            guard let value = proxy.value(atX: x, as: Double.self) else { return }
                            let hour = min(max(Int(value.rounded()), 0), stats.hours.count - 1)
                            withAnimation(Theme.Motion.fastAnimation) {
                                selectedHour = selectedHour == hour ? nil : hour
                            }
                        }
                    )
            }
        }
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: 21, by: 3))) { value in
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)").font(.system(size: 10)).foregroundStyle(Theme.mutedForeground) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(height: 150)
    }

    private var weekdayBars: some View {
        let max = Swift.max(1, stats.weekdays.max() ?? 1)
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.muted.opacity(0.6))
                        RoundedRectangle(cornerRadius: 6).fill(Theme.primary.opacity(0.6))
                            .frame(height: 48 * CGFloat(stats.weekdays[i]) / CGFloat(max))
                    }
                    .frame(height: 48)
                    Text(Self.weekdays[i]).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Self.weekdays[i]): \(stats.weekdays[i]) utazás")
            }
        }
    }
}

extension View {
    /// `rounded-2xl border border-border bg-card`.
    func rideCard() -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// The web's `ChartFrame`: a card with a title, a hint and an optional icon.
struct RideChartFrame<Content: View>: View {
    let title: String
    var hint: String?
    var icon: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).tracking(-0.2).foregroundStyle(Theme.foreground)
                    if let hint { Text(hint).font(.system(size: 11.5)).foregroundStyle(Theme.mutedForeground) }
                }
                Spacer(minLength: 8)
                if let icon { Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.mutedForeground) }
            }
            .padding(.bottom, 16)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .rideCard()
    }
}

struct RideStatTile: View {
    let label: String
    let value: String
    var sub: String?
    var tone: Color = Theme.foreground

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(tone)
                .padding(.top, 6)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let sub {
                Text(sub).font(.system(size: 11)).foregroundStyle(Theme.mutedForeground).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

struct RideRankBars: View {
    struct Row {
        let label: String
        let value: Double
        let display: String
    }

    let rows: [Row]
    let bar: Color

    var body: some View {
        if rows.isEmpty {
            Text("Ehhez még nincs elég mérés.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity, minHeight: 96)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).stroke(Theme.border.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        } else {
            let max = Swift.max(1, rows.map { abs($0.value) }.max() ?? 1)
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1).").font(Theme.mono(11, weight: .regular)).foregroundStyle(Theme.mutedForeground).frame(width: 20, alignment: .trailing)
                        VStack(spacing: 4) {
                            HStack {
                                Text(r.label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(r.display).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.foreground)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.muted)
                                    Capsule().fill(bar).frame(width: proxy.size.width * abs(r.value) / max)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }
}

struct RideChip<Label: View>: View {
    @ViewBuilder let label: () -> Label
    let count: () -> Int

    var body: some View {
        HStack(spacing: 6) {
            label().foregroundStyle(Theme.foreground)
            Text("\(count())×")
                .font(Theme.mono(10.5, weight: .bold))
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 4)
                .background(Theme.primary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.border, lineWidth: 1))
    }
}

private struct RideStopChips: View {
    let stops: [RideStats.StopCount]
    @State private var all = false
    private static let folded = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 6) {
                ForEach(all ? stops : Array(stops.prefix(Self.folded))) { s in
                    RideChip { Text(s.name).font(.system(size: 12.5, weight: .medium)) } count: { s.n }
                }
            }
            if stops.count > Self.folded {
                Button(all ? "Kevesebb" : "Mind a \(stops.count) megálló") {
                    withAnimation(Theme.Motion.normalAnimation) { all.toggle() }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primary)
            }
        }
    }
}

private struct RideRecordCard: View {
    let icon: String
    let label: String
    let value: String
    let legs: [Ride]?
    let day: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5)
            }
            .foregroundStyle(Theme.mutedForeground)
            if let first = legs?.first, let last = legs?.last {
                Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.foreground).padding(.top, 6)
                HStack(spacing: 6) {
                    RouteTile(short: first.route, colorHex: first.color, textHex: first.text, size: .small)
                    Text("\(first.fromStopName ?? "?") → \(last.toStopName ?? "?")").lineLimit(1)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, 4)
                Text(day.string(from: Date(timeIntervalSince1970: first.boardedAt)))
                    .font(.system(size: 11)).foregroundStyle(Theme.mutedForeground).padding(.top, 2)
            } else {
                Text("Még nincs mérés").font(.system(size: 14)).foregroundStyle(Theme.mutedForeground).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
