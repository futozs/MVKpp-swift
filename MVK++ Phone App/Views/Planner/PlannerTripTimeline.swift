//
//  PlannerTripTimeline.swift
//  MVK++ Phone App
//

import SwiftUI

/// The vertical timeline: stops, rides, walks and transfers.
struct PlannerTripTimeline: View {
    let trip: JourneyTrip
    let mode: JourneyMode

    fileprivate enum Rail: Equatable {
        case solid(Color)
        case dashed
    }

    fileprivate struct Sub {
        let text: String
        let sec: Double?
        let title: String
    }

    private enum Row: Identifiable {
        case stop(id: String, time: String, sub: Sub?, name: String, top: Rail?, bottom: Rail?, dot: Color, endpoint: Bool)
        case ride(id: String, rail: Rail, leg: JourneyLeg)
        case walk(id: String, leg: JourneyLeg?, transfer: Bool, transferIndex: Int?)

        var id: String {
            switch self {
            case .stop(let id, _, _, _, _, _, _, _), .ride(let id, _, _), .walk(let id, _, _, _): return id
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .stop(_, let time, let sub, let name, let top, let bottom, let dot, let endpoint):
                    StopRow(time: time, sub: sub, name: name, top: top, bottom: bottom, dot: dot, endpoint: endpoint)
                case .ride(_, let rail, let leg):
                    SegmentRow(rail: rail) { RideBody(leg: leg, mode: mode) }
                case .walk(_, let leg, let transfer, let transferIndex):
                    SegmentRow(rail: .dashed) {
                        WalkBody(leg: leg, isTransfer: transfer) {
                            if let transferIndex { transferBadge(transferIndex) }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Az utazás lépései")
    }

    @ViewBuilder
    private func transferBadge(_ index: Int) -> some View {
        if trip.transferChecks.indices.contains(index) {
            let check = trip.transferChecks[index]
            FlowLayout(spacing: 6, lineSpacing: 6) {
                PlannerTransferBadge(check: check, mode: mode, measured: PastOutcome.transferMeasured(trip, index: index))
                if mode == .now {
                    PlannerTransferWatchButton(check: check)
                }
            }
        }
    }

    private var rows: [Row] {
        let legs = trip.legs
        var rows: [Row] = []
        var ride = -1
        let muted = Theme.mutedForeground
        for (i, leg) in legs.enumerated() {
            let prev = i > 0 ? legs[i - 1] : nil
            let next = i + 1 < legs.count ? legs[i + 1] : nil
            if leg.isTransit {
                ride += 1
                let color = PlannerFormat.routeColor(leg.routeColor)
                rows.append(.stop(id: "b\(i)", time: PlannerFormat.hm(leg.start), sub: boardSub(leg), name: leg.fromName,
                                  top: prev != nil ? .dashed : nil, bottom: .solid(color), dot: color, endpoint: prev == nil))
                rows.append(.ride(id: "r\(i)", rail: .solid(color), leg: leg))
                rows.append(.stop(id: "a\(i)", time: PlannerFormat.hm(leg.end), sub: alightSub(leg), name: leg.toName,
                                  top: .solid(color), bottom: next != nil ? .dashed : nil, dot: color, endpoint: next == nil))
                if let next, next.isTransit {
                    rows.append(.walk(id: "t\(i)", leg: nil, transfer: true, transferIndex: ride))
                }
                continue
            }
            if prev == nil {
                rows.append(.stop(id: "origin", time: PlannerFormat.hm(leg.start), sub: nil, name: leg.fromName,
                                  top: nil, bottom: .dashed, dot: muted, endpoint: true))
            }
            let isTransfer = prev?.isTransit == true && next?.isTransit == true
            rows.append(.walk(id: "w\(i)", leg: leg, transfer: isTransfer, transferIndex: isTransfer ? ride : nil))
            if next == nil {
                rows.append(.stop(id: "dest", time: PlannerFormat.hm(leg.end), sub: nil, name: leg.toName,
                                  top: .dashed, bottom: nil, dot: muted, endpoint: true))
            }
        }
        return rows
    }

    private func boardSub(_ leg: JourneyLeg) -> Sub? {
        if mode == .past {
            guard let a = leg.actual, let ts = a.depTs else { return nil }
            return Sub(text: PlannerFormat.hms(ts), sec: a.depDelayS, title: "Mért indulás")
        }
        guard let d = leg.prediction?.depDelayS, abs(d) >= PlannerFormat.onTimeSec, let sched = leg.schedDep else { return nil }
        return Sub(text: "~\(PlannerFormat.hm(sched + d))", sec: d, title: "Várható indulás")
    }

    private func alightSub(_ leg: JourneyLeg) -> Sub? {
        if mode == .past {
            guard let a = leg.actual, let ts = a.arrTs else { return nil }
            return Sub(text: "\(a.estimated ? "≈" : "")\(PlannerFormat.hms(ts))", sec: a.arrDelayS, title: a.estimated ? "Becsült érkezés" : "Mért érkezés")
        }
        guard let d = leg.prediction?.arrDelayS, abs(d) >= PlannerFormat.onTimeSec, let sched = leg.schedArr else { return nil }
        return Sub(text: "~\(PlannerFormat.hm(sched + d))", sec: d, title: "Várható érkezés")
    }
}

// MARK: - Grid pieces

/// `grid-cols-[3.75rem_1rem_minmax(0,1fr)] gap-x-2.5`
private enum TimelineGrid {
    static let timeWidth: CGFloat = 60
    static let railWidth: CGFloat = 16
    static let gap: CGFloat = 10
    /// The dot's centre from the row's top.
    static let dotY: CGFloat = 10
}

private struct RailLine: View {
    let rail: PlannerTripTimeline.Rail

    var body: some View {
        switch rail {
        case .solid(let color):
            Rectangle().fill(color).frame(width: 3)
        case .dashed:
            GeometryReader { proxy in
                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                }
                .stroke(Theme.mutedForeground.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 4]))
            }
            .frame(width: 2)
        }
    }
}

private struct StopRow: View {
    let time: String
    let sub: PlannerTripTimeline.Sub?
    let name: String
    let top: PlannerTripTimeline.Rail?
    let bottom: PlannerTripTimeline.Rail?
    let dot: Color
    let endpoint: Bool

    var body: some View {
        HStack(alignment: .top, spacing: TimelineGrid.gap) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(time)
                    .font(Theme.mono(13, weight: .semibold))
                    .frame(height: 20)
                    .foregroundStyle(Theme.foreground)
                if let sub {
                    Text(sub.text)
                        .font(Theme.mono(10.5, weight: .regular))
                        .frame(height: 16)
                        .foregroundStyle(PlannerFormat.tone(sub.sec).color)
                        .accessibilityLabel("\(sub.title): \(sub.text)")
                }
            }
            .frame(width: TimelineGrid.timeWidth, alignment: .trailing)
            .padding(.bottom, 4)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if let top { RailLine(rail: top).frame(height: TimelineGrid.dotY) } else { Color.clear.frame(height: TimelineGrid.dotY) }
                    if let bottom { RailLine(rail: bottom).frame(maxHeight: .infinity) } else { Color.clear.frame(maxHeight: .infinity) }
                }
                let size: CGFloat = endpoint ? 14 : 12
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().strokeBorder(dot, lineWidth: 3))
                    .frame(width: size, height: size)
                    .offset(y: TimelineGrid.dotY - size / 2)
            }
            .frame(width: TimelineGrid.railWidth)
            .frame(maxHeight: .infinity)

            Text(name)
                .font(.system(size: endpoint ? 14 : 13, weight: endpoint ? .bold : .semibold))
                .foregroundStyle(Theme.foreground)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, endpoint ? 1 : 2)
                .padding(.bottom, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SegmentRow<Content: View>: View {
    let rail: PlannerTripTimeline.Rail
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: TimelineGrid.gap) {
            Color.clear.frame(width: TimelineGrid.timeWidth, height: 1)
            RailLine(rail: rail)
                .frame(width: TimelineGrid.railWidth)
                .frame(maxHeight: .infinity)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct RideBody: View {
    let leg: JourneyLeg
    let mode: JourneyMode
    @State private var showStops = false

    var body: some View {
        let hops = leg.stopsBetween.count + 1
        let meta = "\(PlannerFormat.minutes(leg.durationSec)) · \(hops) megálló"
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RouteTile(short: PlannerFormat.legTileText(leg), colorHex: leg.routeColor ?? "1FB574", textHex: leg.routeTextColor, size: .small)
                (Text(leg.trainName ?? PlannerFormat.modeNoun(leg.mode)).fontWeight(.semibold).foregroundColor(Theme.foreground)
                    + Text(leg.headsign.map { " · \($0)" } ?? "").foregroundColor(Theme.mutedForeground))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let platform = leg.fromPlatform, !platform.isEmpty {
                    PlannerPlatformBadge(platform: platform, rail: leg.isRail)
                }
            }
            if leg.stopsBetween.isEmpty {
                Text(meta)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.mutedForeground)
            } else {
                Button {
                    withAnimation(Theme.Motion.fastAnimation) { showStops.toggle() }
                } label: {
                    (Text("\(meta) ") + Text("útközben").underline(true, pattern: .dot))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(showStops ? Theme.foreground : Theme.mutedForeground)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showStops ? "kinyitva" : "becsukva")
                if showStops {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(leg.stopsBetween.enumerated()), id: \.offset) { _, name in
                            Text(name)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }
            PlannerLegInsight(leg: leg, mode: mode)
        }
    }
}

private struct WalkBody<Extra: View>: View {
    let leg: JourneyLeg?
    let isTransfer: Bool
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        let what = leg.map { "gyalog \(PlannerFormat.minutes($0.durationSec)) · \(PlannerFormat.distance($0.distanceMeter))" } ?? "ugyanennél a megállónál"
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 11))
                Text(isTransfer ? "Átszállás: \(what)" : what.prefix(1).uppercased() + what.dropFirst())
                    .font(.system(size: 11))
            }
            .foregroundStyle(Theme.mutedForeground)
            extra()
        }
    }
}

/// Track (rail) or bay (bus station) for boarding.
private struct PlannerPlatformBadge: View {
    let platform: String
    let rail: Bool

    var body: some View {
        HStack(spacing: 4) {
            if rail {
                Image(systemName: "tram.fill.tunnel")
                    .font(.system(size: 9))
            }
            Text(platform)
                .font(Theme.mono(10.5, weight: .bold))
            Text(rail ? "vg." : "k.áll.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .fixedSize()
        .accessibilityLabel("\(platform). \(rail ? "vágány" : "kocsiállás")")
    }
}

/// A ride's expected lateness (today and later) or the measured reality (past).
struct PlannerLegInsight: View {
    let leg: JourneyLeg
    let mode: JourneyMode

    var body: some View {
        if mode == .past { actual } else { forecast }
    }

    private func delayText(_ sec: Double?, _ text: String) -> Text {
        Text(text).fontWeight(.semibold).monospacedDigit().foregroundColor(PlannerFormat.tone(sec).color)
    }

    @ViewBuilder
    private var forecast: some View {
        if let p = leg.prediction, p.source != "none", p.depDelayS != nil || p.arrDelayS != nil {
            let p85 = p.arrDelayP85S
            let showWorst = p85.map { $0 >= PlannerFormat.onTimeSec && $0 - (p.arrDelayS ?? 0) >= PlannerFormat.onTimeSec } ?? false
            let live = p.source == "live"
            VStack(alignment: .leading, spacing: 4) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                    GridRow {
                        Text("Indulás").foregroundStyle(Theme.mutedForeground)
                        delayLine(p.depDelayS, worst: nil)
                    }
                    GridRow {
                        Text("Érkezés").foregroundStyle(Theme.mutedForeground)
                        delayLine(p.arrDelayS, worst: showWorst ? p85 : nil)
                    }
                }
                .font(.system(size: 11))

                HStack(spacing: 6) {
                    if live {
                        LiveDot()
                    } else {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                    }
                    Text(PlannerForecast.basisLabel(p))
                        .fontWeight(live ? .semibold : .regular)
                    if live, let vehicleId = p.vehicleId {
                        Group {
                            if leg.isRail {
                                Text("· a vonat úton")
                            } else {
                                Text("· ") + Text(TransitIds.displayVehicleId(vehicleId)).font(Theme.mono(10.5, weight: .regular)) + Text(" úton")
                            }
                        }
                        .fontWeight(.regular)
                        .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(live ? Theme.live : Theme.mutedForeground)
            }
        } else {
            Text("Ehhez a menethez nincs késési adatunk a menetrendi időt mutatjuk.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func delayLine(_ sec: Double?, worst: Double?) -> some View {
        if let sec {
            let base = Text("várhatóan ").foregroundColor(Theme.foreground) + delayText(sec, PlannerFormat.delayForecast(sec))
            if let worst {
                (base + Text(" · rossz esetben ").foregroundColor(Theme.mutedForeground)
                    + Text(PlannerFormat.delayShort(worst)).fontWeight(.semibold).monospacedDigit().foregroundColor(Theme.late))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                base
            }
        } else {
            Text("nincs adat").foregroundStyle(Theme.mutedForeground)
        }
    }

    @ViewBuilder
    private var actual: some View {
        if let a = leg.actual, a.tracked {
            VStack(alignment: .leading, spacing: 2) {
                if let ts = a.depTs, let d = a.depDelayS {
                    (Text("Valójában ") + Text(PlannerFormat.hms(ts)).fontWeight(.semibold).monospacedDigit() + Text("-kor indult (")
                        + delayText(d, PlannerFormat.delayShort(d)) + Text(")")
                        + Text(a.vehicleId.map { ", \(PlannerFormat.vehiclePhrase($0, mode: leg.mode))" } ?? "") + Text("."))
                        .foregroundStyle(Theme.foreground)
                } else {
                    Text("Az indulásról nincs mérés\(a.vehicleId.map { " (jármű: \(TransitIds.displayVehicleId($0)))" } ?? "").")
                        .foregroundStyle(Theme.mutedForeground)
                }
                if let ts = a.arrTs, let d = a.arrDelayS {
                    FlowLayout(spacing: 6, lineSpacing: 2) {
                        (Text("Valójában ") + Text(PlannerFormat.hms(ts)).fontWeight(.semibold).monospacedDigit() + Text("-kor érkezett (")
                            + delayText(d, PlannerFormat.delayShort(d)) + Text(")."))
                            .foregroundStyle(Theme.foreground)
                        if a.estimated {
                            HStack(spacing: 4) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 8))
                                Text("BECSÜLT")
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.4)
                            }
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                            .accessibilityHint("Ennél a megállónál nem volt közvetlen mérés, az időt a jármű pályájából becsültük.")
                        }
                    }
                } else {
                    Text("Az érkezésről nincs mérés.")
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 11))
                Text("Erről a menetről nincs mérés.")
                    .font(.system(size: 11))
            }
            .foregroundStyle(Theme.mutedForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
        }
    }
}
