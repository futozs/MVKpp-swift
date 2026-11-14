//
//  ParkingLots.swift
//  MVK++ Phone App
//

import SwiftUI

/// What every lot card needs to draw its vehicles.
struct ParkingLotContext {
    let now: Double
    let midnight: Double
    let limitS: Double
    let lookup: ParkingRouteLookup
    let history: (String) -> ParkingFleetHistory?
    let onSelect: (String) -> Void
    /// Volán / rail: no depot, so no "silent → pulled in" bar either.
    var regional = false
}

// MARK: - Fleet summary

/// The fleet now: four big numbers and a proportional bar.
struct ParkingFleetSummary: View {
    let counts: ParkingKindCounts
    let facts: [(label: String, value: Text)]

    private struct Segment {
        let key: KeyPath<ParkingKindCounts, Int>
        let label: String
        let color: Color
        let text: Color
    }

    private let segments: [Segment] = [
        Segment(key: \.service, label: "bevetésen", color: Theme.primary, text: Theme.primary),
        Segment(key: \.terminus, label: "végállomáson", color: Theme.park, text: Theme.park),
        Segment(key: \.depot, label: "kocsiszínben", color: Theme.depot.opacity(0.7), text: Theme.depot),
        Segment(key: \.nosignal, label: "jel nélkül", color: Theme.nosignal, text: Theme.nosignal),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                ForEach(segments, id: \.label) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 8, height: 8)
                            Text(s.label)
                                .font(Theme.sans(11.5))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        Text("\(counts[keyPath: s.key])")
                            .font(Theme.sans(26, weight: .bold))
                            .monospacedDigit()
                            .tracking(-0.5)
                            .foregroundStyle(s.text)
                            .contentTransition(.numericText())
                    }
                    .opacity(s.label == "jel nélkül" && counts.nosignal == 0 ? 0.5 : 1)
                }
            }

            if counts.total > 0 {
                GeometryReader { geo in
                    let shown = segments.filter { counts[keyPath: $0.key] > 0 }
                    let gaps = CGFloat(max(0, shown.count - 1)) * 3
                    HStack(spacing: 3) {
                        ForEach(shown, id: \.label) { s in
                            Capsule()
                                .fill(s.color)
                                .frame(width: max(0, (geo.size.width - gaps) * CGFloat(counts[keyPath: s.key]) / CGFloat(max(1, counts.total))))
                        }
                    }
                    .animation(Theme.Motion.normalAnimation, value: counts)
                }
                .frame(height: 10)
                .padding(.top, 16)
                .accessibilityElement()
                .accessibilityLabel(segments.map { "\(counts[keyPath: $0.key]) \($0.label)" }.joined(separator: ", "))
            }

            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.label.uppercased())
                                .font(Theme.sans(10.5, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Theme.mutedForeground)
                            fact.value
                                .font(Theme.sans(13))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1) }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .parkingCard()
    }
}

// MARK: - Terminal lot

/// One terminus: header with the next departure, below it the stalls.
struct ParkingTerminalLotCard: View {
    let lot: ParkingTerminalLot
    let ctx: ParkingLotContext
    let favorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        let next = lot.vehicles.filter { $0.next != nil }.min { ($0.next?.startS ?? 0) < ($1.next?.startS ?? 0) }
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "parkingsign")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.park)
                    .frame(width: 28, height: 28)
                    .background(Theme.park.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lot.name)
                        .font(Theme.sans(15, weight: .bold))
                        .tracking(-0.2)
                        .lineLimit(1)
                    nextLine(next)
                        .font(Theme.sans(11.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("\(lot.vehicles.count)")
                        .font(Theme.mono(14, weight: .bold))
                        .foregroundStyle(Theme.park)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.park.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    ParkingFavoriteButton(active: favorite, name: lot.name, onToggle: onToggleFavorite)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // The stalls: dashed vertical lines between the vehicles, like a real car park.
            Group {
                if lot.vehicles.isEmpty {
                    Text("Most senki sem parkol itt")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .padding(4)
                } else {
                    ParkingAdaptiveGrid(minWidth: 138) {
                        ForEach(lot.vehicles) { v in
                            ParkingTile(v: v, ctx: ctx)
                                .padding(4)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .overlay(alignment: .trailing) {
                                    Rectangle()
                                        .fill(.clear)
                                        .frame(width: 1)
                                        .overlay(Line().stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                                        .padding(.vertical, 8)
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.muted.opacity(0.25))
            .overlay(alignment: .top) { Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1) }
        }
        .parkingCard(border: favorite ? Theme.primary.opacity(0.35) : Theme.border)
    }

    private func nextLine(_ next: ParkingVehicle?) -> Text {
        guard let next, let tip = next.next else { return Text("Nincs ismert indulás innen") }
        return Text("Következő innen: ")
            + Text(tip.route).font(Theme.mono(11.5, weight: .semibold)).foregroundColor(Theme.foreground)
            + Text(" ")
            + Text(ParkingFormat.hm(daySec: tip.startS)).font(Theme.mono(11.5, weight: .regular))
            + Text(" · ")
            + Text(TransitModes.displayVehicleId(next.id)).font(Theme.mono(11.5, weight: .regular))
            + Text(tip.certain ? "" : " (tipp)")
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// One parked vehicle at a terminus.
struct ParkingTile: View {
    let v: ParkingVehicle
    let ctx: ParkingLotContext

    var body: some View {
        // A train's name is longer than a plate ("FLIRT 415 112"): smaller, one line.
        let label = TransitModes.displayVehicleId(v.id)
        let parked = v.since.map { max(0, ctx.now - $0) }
        let silent = (!v.online ? v.lastSeen : nil).map { max(0, ctx.now - $0) }
        let toLimit = silent.flatMap { ctx.regional ? nil : min(1, $0 / ctx.limitS) }
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)

        Button { ctx.onSelect(v.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(Theme.mono(label.count > 9 ? 12.5 : 15, weight: .bold))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    ParkingSignalDot(online: v.online)
                }
                HStack(spacing: 6) {
                    ParkingRouteChip(route: v.lastRoute, lookup: ctx.lookup)
                    Text(parked.map { "áll \(ParkingFormat.duration($0))" } ?? (v.online ? "itt áll" : ""))
                        .lineLimit(1)
                }
                .font(Theme.sans(11))
                .foregroundStyle(Theme.mutedForeground)
                if let toLimit, let silent {
                    ParkingProgressBar(value: toLimit, tint: toLimit > 0.75 ? Theme.nosignal : Theme.park.opacity(0.7))
                        .accessibilityLabel("\(ParkingFormat.duration(silent)) óta nincs jel \(Int((ctx.limitS / 60).rounded())) perc után a kocsiszínbe soroljuk")
                }
                if let tip = v.next {
                    ParkingTipChip(tip: tip, lookup: ctx.lookup, midnight: ctx.midnight, now: ctx.now, variant: .tile)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(v.next?.certain == true ? Theme.primary.opacity(0.4) : Theme.border, lineWidth: 1))
            .mvkShadow(Theme.Shadow.xs)
            .contentShape(shape)
        }
        .buttonStyle(ParkingPressStyle())
    }
}

/// The amber/blue bar of a silent vehicle: time left until it counts as pulled in.
struct ParkingProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.muted)
                Capsule().fill(tint).frame(width: geo.size.width * value)
            }
        }
        .frame(height: 4)
    }
}

struct ParkingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}

// MARK: - Depot lot

/// A depot: the vehicles standing there, grouped by how they got there.
struct ParkingDepotLotCard: View {
    let lot: ParkingDepotLot
    let ctx: ParkingLotContext
    let serviceDate: String
    let favorite: Bool
    let onToggleFavorite: () -> Void

    private let order: [ParkingDepotReason] = [.pullIn, .seen, .timeout, .notToday]

    var body: some View {
        let groups = order.compactMap { reason -> (ParkingDepotReason, [ParkingVehicle])? in
            let list = lot.vehicles.filter { $0.reason == reason }
            return list.isEmpty ? nil : (reason, list)
        }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: lot.id == .tram ? "tram" : "door.garage.closed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.depot)
                    .frame(width: 32, height: 32)
                    .background(Theme.depot.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(lot.name)
                        .font(Theme.sans(15, weight: .bold))
                        .tracking(-0.2)
                        .lineLimit(1)
                    Text(lot.vehicles.isEmpty ? "Most mindenki kint van" : "\(lot.vehicles.count) \(lot.id == .tram ? "villamos" : "busz") nincs bevetésen")
                        .font(Theme.sans(11.5))
                        .foregroundStyle(Theme.mutedForeground)
                }
                Spacer(minLength: 0)
                ParkingFavoriteButton(active: favorite, name: lot.name, onToggle: onToggleFavorite)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1) }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.0) { reason, vehicles in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(ParkingFormat.reasonLabel(reason).uppercased())
                                .tracking(0.6)
                                .foregroundStyle(Theme.mutedForeground)
                            Text("\(vehicles.count)")
                                .font(Theme.mono(11, weight: .semibold))
                                .foregroundStyle(Theme.foreground.opacity(0.8))
                        }
                        .font(Theme.sans(11, weight: .semibold))
                        .padding(.horizontal, 4)
                        .accessibilityHint(ParkingFormat.reasonHint(reason))
                        ParkingAdaptiveGrid(minWidth: 122, spacing: 6) {
                            ForEach(vehicles) { v in
                                ParkingDepotStall(v: v, ctx: ctx, serviceDate: serviceDate)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .parkingCard(border: favorite ? Theme.primary.opacity(0.35) : Theme.border)
    }
}

private struct ParkingDepotStall: View {
    let v: ParkingVehicle
    let ctx: ParkingLotContext
    let serviceDate: String

    var body: some View {
        let h = ctx.history(v.id)
        // Not out yet today: its usual pull-out and how typical that is on such days.
        let habit: String? = {
            guard v.next == nil, let h, let share = h.outShare, v.reason == .notToday else { return nil }
            return "\(h.usualOutS.map { "ált. \(ParkingFormat.hm(daySec: $0)) · " } ?? "")\(ParkingFormat.pct(share))"
        }()
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        Button { ctx.onSelect(v.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(TransitModes.displayVehicleId(v.id))
                        .font(Theme.mono(14, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if v.reason == .seen {
                        ParkingSignalDot(online: true)
                    } else if let h {
                        ParkingPresenceStrip(recent: String(h.recent.suffix(7)))
                    }
                }
                Text(ParkingFormat.depotLine(v, history: h, serviceDate: serviceDate))
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                if let tip = v.next {
                    ParkingTipChip(tip: tip, lookup: ctx.lookup, midnight: ctx.midnight, now: ctx.now, variant: .stall)
                } else if let habit {
                    Text(habit)
                        .font(Theme.mono(10.5, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background.opacity(0.5), in: shape)
            .overlay(shape.strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: v.reason == .notToday ? [4, 3] : [])))
            .contentShape(shape)
        }
        .buttonStyle(ParkingPressStyle())
    }
}

// MARK: - Lists

/// Vehicles that went silent mid-trip; the amber bar shows the time left to
/// the one-hour limit.
struct ParkingNoSignalList: View {
    let vehicles: [ParkingVehicle]
    let now: Double
    let limitS: Double
    let onSelect: (String) -> Void
    let lookup: ParkingRouteLookup

    var body: some View {
        if !vehicles.isEmpty {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash").foregroundStyle(Theme.nosignal)
                    Text("Jel nélkül")
                    Text("\(vehicles.count)").font(Theme.mono(14, weight: .bold)).foregroundStyle(Theme.nosignal)
                }
                .font(Theme.sans(14, weight: .bold))
                Text("Menet közben elnémultak. Ha \(Int((limitS / 60).rounded())) percen belül nem jelentkeznek, a kocsiszínbe soroljuk őket.")
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.top, 2)
                ParkingAdaptiveGrid(minWidth: 160, spacing: 8) {
                    ForEach(vehicles) { v in
                        let silent = v.lastSeen.map { max(0, now - $0) } ?? 0
                        let tile = RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                        Button { onSelect(v.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(TransitModes.displayVehicleId(v.id)).font(Theme.mono(15, weight: .bold))
                                    Spacer(minLength: 0)
                                    ParkingRouteChip(route: v.lastRoute, lookup: lookup)
                                }
                                Text("\(v.place.map { "\($0) közelében · " } ?? "")\(ParkingFormat.duration(silent))")
                                    .font(Theme.sans(11))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .lineLimit(1)
                                ParkingProgressBar(value: min(1, silent / limitS), tint: Theme.nosignal)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.card, in: tile)
                            .overlay(tile.strokeBorder(Theme.border, lineWidth: 1))
                            .contentShape(tile)
                        }
                        .buttonStyle(ParkingPressStyle())
                    }
                }
                .padding(.top, 12)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.nosignal.opacity(0.06), in: shape)
            .overlay(shape.strokeBorder(Theme.nosignal.opacity(0.3), lineWidth: 1))
        }
    }
}

/// The vehicles running a trip now; collapsible so the lots stay in front.
struct ParkingServiceList: View {
    let vehicles: [ParkingServiceVehicle]
    let onSelect: (String) -> Void
    let lookup: ParkingRouteLookup
    @State private var open = false

    var body: some View {
        if !vehicles.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(Theme.Motion.normalAnimation) { open.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.primary).frame(width: 8, height: 8)
                        Text("Bevetésen")
                        Text("\(vehicles.count)").font(Theme.mono(14, weight: .bold)).foregroundStyle(Theme.primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .font(Theme.sans(14, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if open {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(vehicles) { v in
                            let chip = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            Button { onSelect(v.id) } label: {
                                HStack(spacing: 6) {
                                    Text(TransitModes.displayVehicleId(v.id)).font(Theme.mono(12.5, weight: .bold))
                                    if v.route != nil {
                                        ParkingRouteChip(route: v.route, lookup: lookup)
                                    } else {
                                        Text("úton").font(Theme.sans(10.5)).foregroundStyle(Theme.mutedForeground)
                                    }
                                }
                                .padding(.leading, 8)
                                .padding(.trailing, 6)
                                .padding(.vertical, 4)
                                .background(Theme.background.opacity(0.6), in: chip)
                                .overlay(chip.strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: v.deadhead ? [4, 3] : [])))
                            }
                            .buttonStyle(ParkingPressStyle())
                            .accessibilityHint(v.deadhead ? "menet nélkül úton" : (v.headsign ?? ""))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1) }
                    .transition(.opacity)
                }
            }
            .parkingCard()
        }
    }
}
