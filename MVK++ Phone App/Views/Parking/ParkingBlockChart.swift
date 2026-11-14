//
//  ParkingBlockChart.swift
//  MVK++ Phone App
//

import SwiftUI

/// Forda-tábla: the fleet's day on one timeline. A solid bar is a trip run
/// or running (from its real start), a dashed one the block plan's next trip;
/// the fainter, the less certain the tip.
struct ParkingBlockChart: View {
    let lookup: ParkingRouteLookup
    let kind: ParkingScreen.KindFilter
    let query: String
    let onSelect: (String) -> Void

    enum SortMode: Hashable { case route, first, id }

    @StateObject private var model = ParkingBlocksModel()
    @State private var ppm: CGFloat = 2
    @State private var sort: SortMode = .route
    @State private var offset: CGPoint = .zero
    private static let nowAnchor = "now"
    @State private var centered = false

    private let rowH: CGFloat = 30
    private let headerH: CGFloat = 28
    private let leftW: CGFloat = 64
    private let hour = 3600

    private struct BlockGroup: Identifiable {
        let route: String?
        let rows: [ParkingBlockRow]
        var id: String { route ?? "all" }
    }

    var body: some View {
        Group {
            if let data = model.data {
                chart(data)
            } else {
                ParkingEmptyBox(text: model.error ?? "A forda-tábla betöltése…", verticalPadding: 48)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: - Data shaping

    private func filtered(_ data: ParkingBlocks) -> [ParkingBlockRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return data.vehicles.filter { v in
            (kind == .all || v.kind.rawValue == kind.rawValue)
                && (q.isEmpty || v.id.lowercased().hasPrefix(q) || v.runs.contains { $0.r.lowercased() == q } || v.plan.contains { $0.r.lowercased() == q })
        }
    }

    /// The vehicle's "current" trip: the running one, else the next tip, else
    /// the last one run.
    private func anchor(_ v: ParkingBlockRow) -> (route: String, start: Int) {
        if let running = v.runs.first(where: { $0.st == "running" }) { return (running.r, running.as ?? running.s) }
        if let next = v.plan.first { return (next.r, next.s) }
        if let last = v.runs.last { return (last.r, last.s) }
        return ("?", Int.max)
    }

    private func numeric(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric], locale: Locale(identifier: "hu_HU")) == .orderedAscending
    }

    /// Grouped by route, within a group by the current trip's start — like a timetable.
    private func groups(_ rows: [ParkingBlockRow]) -> [BlockGroup] {
        switch sort {
        case .id: return [BlockGroup(route: nil, rows: rows.sorted { numeric($0.id, $1.id) })]
        case .first: return [BlockGroup(route: nil, rows: rows)]
        case .route:
            let byRoute = Dictionary(grouping: rows) { anchor($0).route }
            return byRoute.keys.sorted(by: numeric).map { route in
                BlockGroup(route: route, rows: (byRoute[route] ?? []).sorted { anchor($0).start < anchor($1).start })
            }
        }
    }

    private func span(_ data: ParkingBlocks) -> (Int, Int) {
        var lo = 4 * hour
        var hi = 24 * hour
        for v in data.vehicles {
            for r in v.runs { lo = min(lo, r.s); hi = max(hi, r.e) }
            for p in v.plan { lo = min(lo, p.s); hi = max(hi, p.e) }
        }
        let t0 = (lo / hour) * hour
        let t1 = min(27 * hour, Int((Double(hi) / Double(hour)).rounded(.up)) * hour)
        return (t0, t1)
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(_ data: ParkingBlocks) -> some View {
        let (t0, t1) = span(data)
        let x: (Int) -> CGFloat = { CGFloat($0 - t0) / 60 * ppm }
        let rows = filtered(data)
        let grouped = groups(rows)
        let width = x(t1)
        let bodyHeight = grouped.reduce(CGFloat(0)) { $0 + ($1.route == nil ? 0 : headerH) + CGFloat($1.rows.count) * rowH }
        let hours = Array(stride(from: t0, through: t1, by: hour))

        VStack(spacing: 0) {
            controls
            ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: leftW + x(data.now), height: 1)
                        Color.clear.frame(width: 1, height: 1).id(Self.nowAnchor)
                    }

                    Canvas { ctx, _ in
                        drawRows(ctx, grouped: grouped, data: data, x: x, width: width)
                        let nowX = leftW + x(data.now)
                        ctx.fill(Path(CGRect(x: nowX - 1, y: headerH, width: 2, height: bodyHeight)), with: .color(Theme.primary.opacity(0.8)))
                    }
                    .frame(width: width + leftW, height: headerH + bodyHeight)

                    leftColumn(grouped)
                        .background(alignment: .leading) {
                            // Covers bars that scroll in under the sticky column's left edge.
                            Theme.card.frame(width: 24).offset(x: -24)
                        }
                        .offset(x: max(0, offset.x), y: headerH)

                    hourBar(hours, x: x, width: width)
                        .offset(y: max(0, offset.y))
                }
                .frame(width: width + leftW, height: headerH + bodyHeight, alignment: .topLeading)

                if rows.isEmpty {
                    Text("Nincs ilyen jármű.")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.vertical, 32)
                }
            }
            .onScrollGeometryChange(for: CGPoint.self) { $0.contentOffset } action: { _, new in offset = new }
            .containerRelativeFrame(.vertical) { height, _ in
                min(height * 0.7, headerH + bodyHeight + (rows.isEmpty ? 84 : 0))
            }
            .task {
                guard !centered else { return }
                // First load: "now" in the middle, once the content has a size.
                try? await Task.sleep(for: .milliseconds(100))
                centered = true
                proxy.scrollTo(Self.nowAnchor, anchor: UnitPoint(x: 0.55, y: 0))
            }
            }
        }
        .parkingCard()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 16, lineSpacing: 4) {
                legend("lefutott / fut") { RoundedRectangle(cornerRadius: 5).fill(Theme.foreground.opacity(0.7)).frame(width: 20, height: 10) }
                legend("tipp (forda-terv)") {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.foreground.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: 20, height: 10)
                }
                legend("most") { Rectangle().fill(Theme.primary).frame(width: 2, height: 12) }
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ParkingSegmented(options: [(SortMode.route, "Vonal szerint"), (.first, "Kiállás szerint"), (.id, "Rendszám")], selection: $sort, compact: true)
                    .fixedSize()
                ParkingSegmented(options: [(CGFloat(2), "Nap"), (3, "Félnap"), (5, "Közeli")], selection: $ppm, compact: true)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1) }
    }

    private func legend<Swatch: View>(_ text: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 6) {
            swatch()
            Text(text)
        }
        .font(Theme.sans(11.5))
        .foregroundStyle(Theme.mutedForeground)
    }

    private func hourBar(_ hours: [Int], x: @escaping (Int) -> CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.card)
            ForEach(hours, id: \.self) { h in
                Text(ParkingFormat.hm(daySec: h))
                    .font(Theme.mono(10.5, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize()
                    .position(x: leftW + x(h), y: headerH / 2)
            }
            Rectangle().fill(Theme.card)
                .frame(width: leftW, height: headerH)
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
                .offset(x: max(0, offset.x))
        }
        .frame(width: width + leftW, height: headerH)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func leftColumn(_ grouped: [BlockGroup]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(grouped) { g in
                if let route = g.route {
                    HStack(spacing: 8) {
                        ParkingRouteChip(route: route, lookup: lookup)
                        Text("\(g.rows.count) jármű")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: headerH, alignment: .leading)
                    .background(Theme.muted.opacity(0.9))
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
                }
                ForEach(g.rows) { v in
                    Button { onSelect(v.id) } label: {
                        Text(TransitModes.displayVehicleId(v.id))
                            .font(Theme.mono(12, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 8)
                            .frame(width: leftW, height: rowH, alignment: .leading)
                            .background(Theme.card)
                            .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func drawRows(_ ctx: GraphicsContext, grouped: [BlockGroup], data: ParkingBlocks, x: (Int) -> CGFloat, width: CGFloat) {
        var y = headerH
        for g in grouped {
            if g.route != nil {
                ctx.fill(Path(CGRect(x: 0, y: y, width: width + leftW, height: headerH)), with: .color(Theme.muted.opacity(0.4)))
                ctx.fill(Path(CGRect(x: 0, y: y + headerH - 1, width: width + leftW, height: 1)), with: .color(Theme.border))
                y += headerH
            }
            for v in g.rows {
                for r in v.runs {
                    let s = r.as ?? r.s
                    let e = r.ae ?? (r.st == "running" ? max(data.now, s + 60) : r.e)
                    bar(ctx, left: leftW + x(s), width: x(e) - x(s), y: y, route: r.r, solid: true, running: r.st == "running", confidence: 1)
                }
                for p in v.plan {
                    bar(ctx, left: leftW + x(p.s), width: x(p.e) - x(p.s), y: y, route: p.r, solid: false, running: false, confidence: p.c ?? 0.3)
                }
                ctx.fill(Path(CGRect(x: 0, y: y + rowH - 1, width: width + leftW, height: 1)), with: .color(Theme.border.opacity(0.4)))
                y += rowH
            }
        }
    }

    private func bar(_ ctx: GraphicsContext, left: CGFloat, width: CGFloat, y: CGFloat, route: String, solid: Bool, running: Bool, confidence: Double) {
        let r = lookup(route)
        let bg = ParkingStyle.hex(r?.color, ParkingStyle.chipFallback)
        let fg = ParkingStyle.hex(r?.text, "FFFFFF")
        let rect = CGRect(x: left, y: y + 5, width: max(2, width), height: 20)
        let shape = Path(roundedRect: rect, cornerRadius: 4)
        if solid {
            ctx.fill(shape, with: .color(bg))
            if running {
                ctx.stroke(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 6), with: .color(Theme.primary), lineWidth: 2)
            }
        } else {
            var faded = ctx
            faded.opacity = 0.35 + 0.65 * min(1, confidence)
            faded.fill(shape, with: .color(bg.opacity(0.13)))
            faded.stroke(shape, with: .color(bg), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        }
        guard width >= 22 else { return }
        var label = ctx
        if !solid { label.opacity = 0.35 + 0.65 * min(1, confidence) }
        label.clip(to: Path(rect))
        label.draw(
            Text(route).font(Theme.mono(10.5, weight: .bold)).foregroundStyle(solid ? fg : bg),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }
}
