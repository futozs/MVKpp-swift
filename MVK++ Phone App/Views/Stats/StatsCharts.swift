//
//  StatsCharts.swift
//  MVK++ Phone App
//

import Charts
import SwiftUI

// The web's `components/charts/Charts.tsx` on Swift Charts: thin marks
// (bars at most 24 pt, 4 pt rounding), a hairline grid, round axis values,
// text in the text colour (the mark carries the colour), and a tooltip on
// every chart — value first, label after. The tooltip only adds detail: the
// axis and labels carry the essentials.

// MARK: - Frame, empty state, tile

struct StatsChartFrame<Content: View, Action: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder var action: () -> Action
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.foreground)
                    if let hint {
                        Text(hint)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                action()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsCard()
    }
}

extension StatsChartFrame where Action == EmptyView {
    init(title: String, hint: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.hint = hint
        self.action = { EmptyView() }
        self.content = content
    }
}

extension View {
    /// `rounded-2xl border border-border bg-card`
    func statsCard(radius: CGFloat = 16, fill: Color = Theme.card, stroke: Color = Theme.border) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(fill, in: shape).overlay(shape.strokeBorder(stroke, lineWidth: 1))
    }

    /// `rounded-xl border border-dashed`
    func statsDashed(radius: CGFloat = 12, fill: Color = .clear) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(fill, in: shape)
            .overlay(shape.strokeBorder(Theme.border.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

struct StatsEmptyChart: View {
    var text = "Ehhez még nincs elég mérés."

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.mutedForeground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: 96)
            .statsDashed()
    }
}

enum StatsTone {
    case standard, late, early, ontime, live

    var color: Color {
        switch self {
        case .standard: return Theme.foreground
        case .late: return Theme.late
        case .early: return Theme.early
        case .ontime: return Theme.ontime
        case .live: return Theme.live
        }
    }
}

struct StatsStatTile: View {
    let label: String
    let value: String
    var sub: String?
    var tone: StatsTone = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(2)
            Text(value.isEmpty ? " " : value)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(tone.color)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .padding(.top, 6)
            if let sub {
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .statsCard(radius: 16)
    }
}

/// `grid grid-cols-2 gap-2`
struct StatsTileGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            content()
        }
    }
}

/// The floating chart tooltip: value strong, label faint.
struct StatsTip: View {
    let value: String
    var label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.foreground)
            if let label {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.popover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .mvkShadow(Theme.Shadow.lg)
        .fixedSize()
    }
}

// MARK: - Scale helpers

enum StatsScale {
    /// The nearest round upper bound (1, 2, 2.5, 5 × 10ⁿ).
    static func niceCeil(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let p = pow(10, floor(log10(v)))
        let f = v / p
        return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * p
    }

    /// A round step (1, 2, 5 × 10ⁿ).
    static func niceStep(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let p = pow(10, floor(log10(v)))
        let f = v / p
        return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p
    }
}

// MARK: - Bar chart

struct StatsBarDatum: Identifiable {
    let id = UUID()
    let label: String
    let value: Double?
    /// Meaningful colour: late / early / on time, or any other mark colour.
    var tone: Color = Theme.primary
    /// Full tooltip text; replaces "value + label" when given.
    var title: String?
}

struct StatsBarChart: View {
    let data: [StatsBarDatum]
    var height: CGFloat = 176
    var unit = ""
    var maxValue: Double?
    var labelEvery: Int?

    @State private var selected: String?

    var body: some View {
        if data.isEmpty {
            StatsEmptyChart()
        } else {
            GeometryReader { geo in
                chart(width: geo.size.width)
            }
            .frame(height: height)
        }
    }

    private func chart(width: CGFloat) -> some View {
        let values = data.map { $0.value ?? 0 }
        let max = StatsScale.niceCeil(maxValue ?? Swift.max(0, values.max() ?? 0))
        let minRaw = Swift.min(0, values.min() ?? 0)
        let min = minRaw < 0 ? -StatsScale.niceCeil(-minRaw) : 0
        let ticks = min < 0 ? [min, 0, max] : [0, max / 2, max]
        let innerW = Swift.max(width, 240) - 42
        let step = innerW / CGFloat(data.count)
        let barW = Swift.max(2, Swift.min(24, step - 2))
        let every = Swift.max(labelEvery ?? 1, Int(ceil(34 / step)))
        let selectedIndex = selected.flatMap(Int.init)

        return Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { i, d in
                if let v = d.value, v != 0 {
                    BarMark(x: .value("i", String(i)), y: .value("v", v), width: .fixed(barW))
                        .foregroundStyle(d.tone)
                        .cornerRadius(Swift.min(4, barW / 2))
                        .opacity(selectedIndex == nil || selectedIndex == i ? 1 : 0.4)
                        .annotation(position: v < 0 ? .bottom : .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            if selectedIndex == i { tip(d) }
                        }
                } else {
                    BarMark(x: .value("i", String(i)), y: .value("v", 0), width: .fixed(barW))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            if selectedIndex == i { tip(d) }
                        }
                }
            }
            RuleMark(y: .value("0", 0))
                .foregroundStyle(Theme.mutedForeground.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYScale(domain: min...max)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Theme.border.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(StatsFormat.tick(v))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: data.indices.map(String.init)) { value in
                if let raw = value.as(String.self), let i = Int(raw), i % every == 0, every == 1 || i + every / 2 < data.count {
                    AxisValueLabel(centered: true, collisionResolution: .disabled) {
                        Text(data[i].label)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize()
                    }
                }
            }
        }
        .chartXSelection(value: $selected)
        .padding(.top, 12)
    }

    private func tip(_ d: StatsBarDatum) -> some View {
        if let title = d.title { return StatsTip(value: title) }
        let value = d.value.map { "\(StatsFormat.plain($0))\(unit)" } ?? "nincs adat"
        return StatsTip(value: value, label: d.label)
    }
}

/// Delay distribution: early / on time / late by colour.
struct StatsDelayHistogram: View {
    let buckets: [(min: Int, n: Int)]
    var height: CGFloat = 160

    var body: some View {
        if !buckets.contains(where: { $0.n > 0 }) {
            StatsEmptyChart()
        } else {
            StatsBarChart(
                data: buckets.map { b in
                    StatsBarDatum(
                        label: b.min == 0 ? "0" : "\(b.min > 0 ? "+" : "")\(b.min)",
                        value: Double(b.n),
                        tone: b.min < -1 ? Theme.early : b.min > 5 ? Theme.late : Theme.ontime,
                        title: "\(b.n) érkezés · \(b.min > 0 ? "+" : "")\(b.min)…\(b.min + 1) perc"
                    )
                },
                height: height
            )
        }
    }
}

// MARK: - Line chart

struct StatsLinePoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double?
}

struct StatsLineChart: View {
    let data: [StatsLinePoint]
    var height: CGFloat = 180
    var unit = ""
    var zeroLine = false

    @State private var selected: Int?

    var body: some View {
        let points = data.filter { $0.value != nil }
        if points.count < 2 {
            StatsEmptyChart(text: "Legalább két nap adata kell a trendhez.")
        } else {
            chart
        }
    }

    private struct Segmented: Identifiable {
        let id: Int
        let index: Int
        let value: Double
        let segment: Int
    }

    private var chart: some View {
        let vals = data.compactMap(\.value)
        var lo = vals.min() ?? 0
        var hi = vals.max() ?? 0
        if zeroLine {
            lo = min(lo, 0)
            hi = max(hi, 0)
        }
        let step = StatsScale.niceStep(((hi - lo) != 0 ? (hi - lo) : (abs(hi) != 0 ? abs(hi) : 1)) / 3)
        lo = floor(lo / step) * step
        hi = ceil(hi / step) * step
        if hi == lo { hi = lo + step }
        var ticks: [Double] = []
        var t = lo
        while t <= hi + step / 1000 {
            ticks.append((t * 1000).rounded() / 1000)
            t += step
        }
        var segment = 0
        var rows: [Segmented] = []
        for (i, d) in data.enumerated() {
            guard let v = d.value else {
                segment += 1
                continue
            }
            rows.append(Segmented(id: i, index: i, value: v, segment: segment))
        }
        let base = zeroLine && lo < 0 && hi > 0 ? 0 : lo
        let last = rows.last
        let mid = (data.count - 1) / 2
        let labelIndices = data.count > 4 ? [0, mid, data.count - 1] : [0, data.count - 1]

        return Chart {
            ForEach(rows) { r in
                AreaMark(x: .value("i", r.index), yStart: .value("b", base), yEnd: .value("v", r.value), series: .value("s", "a\(r.segment)"))
                    .foregroundStyle(Theme.primary.opacity(0.10))
                LineMark(x: .value("i", r.index), y: .value("v", r.value), series: .value("s", "l\(r.segment)"))
                    .foregroundStyle(Theme.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if zeroLine && lo < 0 && hi > 0 {
                RuleMark(y: .value("0", 0))
                    .foregroundStyle(Theme.mutedForeground.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            if let last {
                PointMark(x: .value("i", last.index), y: .value("v", last.value))
                    .symbol {
                        dot(4).overlay(alignment: .leading) {
                            Text(StatsFormat.tick(last.value))
                                .font(.system(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.foreground)
                                .fixedSize()
                                .offset(x: 15)
                        }
                    }
            }
            if let selected, let v = data[statsSafe: selected]?.value {
                RuleMark(x: .value("i", selected))
                    .foregroundStyle(Theme.mutedForeground.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        StatsTip(value: "\(StatsFormat.plain(v))\(unit)", label: data[selected].label)
                    }
                PointMark(x: .value("i", selected), y: .value("v", v))
                    .symbol { dot(4.5) }
            }
        }
        .chartXScale(domain: 0...max(1, data.count - 1), range: .plotDimension(startPadding: 0, endPadding: 30))
        .chartYScale(domain: lo...hi)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Theme.border.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(StatsFormat.tick(v))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: labelIndices) { value in
                if let i = value.as(Int.self), let label = data[statsSafe: i]?.label {
                    AxisValueLabel(anchor: i == 0 ? .topLeading : i == data.count - 1 ? .topTrailing : .top) {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
        }
        .chartXSelection(value: $selected)
        .padding(.top, 14)
        .frame(height: height)
    }

    private func dot(_ r: CGFloat) -> some View {
        Circle()
            .fill(Theme.primary)
            .frame(width: r * 2, height: r * 2)
            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
    }
}

extension Array {
    subscript(statsSafe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Donut

struct StatsDonutSlice: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    var color: String?
}

struct StatsDonut: View {
    let slices: [StatsDonutSlice]
    var size: CGFloat = 150
    var centerLabel: String?
    var centerSub: String?

    @State private var hover: Int?

    var body: some View {
        let total = slices.reduce(0) { $0 + $1.value }
        if total <= 0 {
            StatsEmptyChart()
        } else {
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Theme.muted, lineWidth: 14)
                        .padding(9)
                    Chart(Array(slices.enumerated()), id: \.offset) { i, s in
                        SectorMark(
                            angle: .value("v", s.value),
                            innerRadius: .ratio(0.79),
                            outerRadius: .ratio(0.97),
                            angularInset: slices.count > 1 ? 1 : 0
                        )
                        .foregroundStyle(color(s))
                        .opacity(hover == nil || hover == i ? 1 : 0.35)
                    }
                    .chartLegend(.hidden)
                    .chartAngleSelection(value: Binding(
                        get: { nil as Double? },
                        set: { angle in hover = angle.flatMap { sliceIndex(at: $0) } }
                    ))
                    VStack(spacing: 4) {
                        Text(hover.map { "\(pct(slices[$0].value, total))%" } ?? centerLabel ?? "")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.foreground)
                        if let hover {
                            Text(slices[hover].label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.mutedForeground)
                                .lineLimit(1)
                                .frame(maxWidth: size * 0.8)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: size, height: size)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(slices.prefix(6).enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(color(s)).frame(width: 10, height: 10)
                            Text(s.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.foreground)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(pct(s.value, total))%")
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(hover == i ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { hover = hover == i ? nil : i }
                    }
                    if slices.count > 6 {
                        Text("+ \(slices.count - 6) további")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.horizontal, 4)
                    }
                    if let centerSub {
                        Text(centerSub)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func color(_ s: StatsDonutSlice) -> Color {
        s.color.map { Theme.hex($0) } ?? Theme.primary
    }

    private func pct(_ v: Double, _ total: Double) -> Int {
        Int((v / total * 100).rounded())
    }

    private func sliceIndex(at angle: Double) -> Int? {
        var acc = 0.0
        for (i, s) in slices.enumerated() {
            acc += s.value
            if angle <= acc { return i }
        }
        return nil
    }
}

// MARK: - Hourly heat strip

struct StatsHourCell: Identifiable {
    let hour: Int
    let value: Double?
    let title: String

    var id: Int { hour }
}

/// The web's `animate-live-pulse` dot in any colour (the red "something is
/// missing right now" signal).
struct StatsPulseDot: View {
    let color: Color
    var size: CGFloat = 8

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.5))
                .scaleEffect(pulsing ? 2.2 : 1)
                .opacity(pulsing ? 0 : 0.8)
            Circle().fill(color)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true }
        }
        .accessibilityHidden(true)
    }
}

struct StatsHourHeat: View {
    let cells: [StatsHourCell]
    var legend: String?

    @State private var hover: Int?

    var body: some View {
        let withData = cells.compactMap(\.value)
        if withData.isEmpty {
            StatsEmptyChart()
        } else {
            let max = withData.max() ?? 0
            let min = withData.min() ?? 0
            VStack(alignment: .leading, spacing: 10) {
                if let hover, let cell = cells[statsSafe: hover] {
                    StatsTip(value: cell.title)
                        .frame(maxWidth: .infinity)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 12), spacing: 4) {
                    ForEach(Array(cells.enumerated()), id: \.element.id) { i, c in
                        let alpha = c.value.map { 0.14 + (max == min ? 0.5 : ($0 - min) / (max - min)) * 0.8 }
                        Text(StatsFormat.serviceHour(c.hour))
                            .font(.system(size: 9.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(alpha == nil ? Theme.mutedForeground.opacity(0.5) : (alpha ?? 0) > 0.6 ? Theme.primaryForeground : Theme.foreground)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background {
                                let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                                if let alpha {
                                    shape.fill(Theme.primary.opacity(alpha))
                                } else {
                                    shape.strokeBorder(Theme.border.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                }
                            }
                            .overlay {
                                if hover == i, c.value != nil {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(Theme.foreground.opacity(0.6), lineWidth: 2)
                                }
                            }
                            .onTapGesture { hover = hover == i ? nil : i }
                    }
                }
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(StatsFormat.tick(min)).monospacedDigit()
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.primary.opacity(0.14), Theme.primary.opacity(0.94)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 80, height: 8)
                        Text(StatsFormat.tick(max)).monospacedDigit()
                    }
                    if let legend { Text(legend) }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.mutedForeground)
            }
        }
    }
}

// MARK: - Ranking

struct StatsRankRow: Identifiable {
    let id = UUID()
    var label: AnyView
    var sub: String?
    let value: Double
    var display: String?
    /// The bar colour when it does not show lateness (default late).
    var bar: Color = Theme.late.opacity(0.8)

    init(label: String, sub: String? = nil, value: Double, display: String? = nil, bar: Color = Theme.late.opacity(0.8)) {
        self.label = AnyView(
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
        )
        self.sub = sub
        self.value = value
        self.display = display
        self.bar = bar
    }

    init<Label: View>(sub: String? = nil, value: Double, display: String? = nil, bar: Color = Theme.late.opacity(0.8), @ViewBuilder label: () -> Label) {
        self.label = AnyView(label())
        self.sub = sub
        self.value = value
        self.display = display
        self.bar = bar
    }
}

struct StatsRankBars: View {
    let rows: [StatsRankRow]
    var unit = ""

    var body: some View {
        if rows.isEmpty {
            StatsEmptyChart()
        } else {
            let max = Swift.max(rows.map { abs($0.value) }.max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1).")
                            .font(Theme.mono(11, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: 20, alignment: .trailing)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    r.label
                                    if let sub = r.sub {
                                        Text(sub)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.mutedForeground)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(r.display ?? "\(StatsFormat.plain(r.value))\(unit)")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.foreground)
                                    .fixedSize()
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.muted)
                                    Capsule().fill(r.bar).frame(width: geo.size.width * abs(r.value) / max)
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
