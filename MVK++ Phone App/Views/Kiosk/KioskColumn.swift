//
//  KioskColumn.swift
//  MVK++ Phone App
//

import SwiftUI

/// One stop's column on the board — the large version of the Megállófigyelő
/// card: the next departure highlighted on top (where it is, which vehicle is
/// coming), the rest below. Every size is a multiple of `em`, which the
/// kiosk fits to the screen.
struct KioskColumn: View {
    let stop: Stop?
    let stopId: String
    let rows: Int
    let em: CGFloat

    @StateObject private var board: KioskBoardModel
    @ObservedObject private var local = LocalStore.shared

    init(stop: Stop?, stopId: String, rows: Int, em: CGFloat, boardKey: String) {
        self.stop = stop
        self.stopId = stopId
        self.rows = rows
        self.em = em
        _board = StateObject(wrappedValue: KioskBoardModel(stopId: stopId, boardKey: boardKey))
    }

    private var showPredicted: Bool { local.bool(WatchFeatures.Feature.predictedVehicle.key) }

    var body: some View {
        let arrivals = board.data?.arrivals ?? []
        let name = stop?.name ?? board.data?.stop.name ?? stopId
        let code: String? = TransitModes.isRegionalId(stopId)
            ? (stop.map(KioskStops.kindLabel) ?? KioskStops.kindLabel(id: stopId))
            : (stop?.code ?? board.data?.stop.code)
        let shape = RoundedRectangle(cornerRadius: 0.9 * em, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0.6 * em) {
                Text(name)
                    .font(.system(size: 1.35 * em, weight: .heavy))
                    .tracking(-0.02 * em)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let code {
                    Text(code)
                        .font(Theme.mono(0.7 * em, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 1.1 * em)
            .padding(.top, 0.9 * em)
            .padding(.bottom, 0.6 * em)

            if let next = arrivals.first {
                KioskFeatured(a: next, em: em, showPredicted: showPredicted)
                VStack(spacing: 0) {
                    ForEach(Array(arrivals.dropFirst().prefix(rows).enumerated()), id: \.offset) { index, a in
                        if index > 0 { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
                        KioskRow(a: a, em: em, showPredicted: showPredicted)
                    }
                }
                .padding(.horizontal, 1.1 * em)
                Spacer(minLength: 0)
            } else {
                Text(board.error != nil ? "A megálló adatai most nem érhetők el." : board.data != nil ? "A következő órában nincs innen induló járat." : "Betöltés…")
                    .font(.system(size: 0.9 * em))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, em)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.card, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
        .onAppear { board.start() }
        .onDisappear { board.stop() }
    }
}

private struct KioskTile: View {
    let a: KioskArrival
    let em: CGFloat
    var big = false

    var body: some View {
        let size = big ? 1.15 * em : 0.9 * em
        Text(a.tileText)
            .font(Theme.mono(size, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 0.3 * size)
            .frame(minWidth: (big ? 2.9 : 2.4) * size, minHeight: (big ? 2.1 : 1.7) * size)
            .foregroundStyle(ParkingStyle.hex(a.text, "FFFFFF"))
            .background(ParkingStyle.hex(a.color, ParkingStyle.chipFallback), in: RoundedRectangle(cornerRadius: 0.35 * size, style: .continuous))
    }
}

/// Track (rail) or bay (coach station); a change is highlighted.
private struct KioskPlatform: View {
    let a: KioskArrival
    let size: CGFloat

    var body: some View {
        if let platform = a.platform, !platform.isEmpty {
            let predicted = a.platformPredicted == true
            let changed = a.platformChanged == true
            let shape = RoundedRectangle(cornerRadius: 0.3 * size, style: .continuous)
            HStack(spacing: 0.2 * size) {
                Text("\(predicted ? "~" : "")\(platform)")
                    .font(Theme.mono(size, weight: .bold))
                Text(a.isRail ? "vg." : "k.áll.")
                    .font(.system(size: 0.85 * size, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .foregroundStyle(predicted ? Theme.mutedForeground : changed ? Theme.late : Theme.foreground)
            .padding(.horizontal, 0.35 * size)
            .background(predicted ? .clear : changed ? Theme.late.opacity(0.12) : Theme.muted, in: shape)
            .overlay(shape.strokeBorder(
                predicted ? Theme.mutedForeground.opacity(0.5) : changed ? Theme.late.opacity(0.5) : Theme.border,
                style: StrokeStyle(lineWidth: 1, dash: predicted ? [3, 2] : [])
            ))
            .fixedSize()
            .accessibilityLabel("\(predicted ? "Várhatóan a " : "")\(platform). \(a.isRail ? "vágány" : "kocsiállás")")
        }
    }
}

/// Delay as text and colour, the measured delay first.
private struct KioskDelay: View {
    let a: KioskArrival
    let size: CGFloat

    var body: some View {
        if a.isCancelled {
            Text("TÖRÖLVE")
                .font(.system(size: size, weight: .bold))
                .tracking(0.04 * size)
                .foregroundStyle(Theme.late)
        } else {
            let delay = (a.measuredDelaySec ?? a.delaySec).map { Int($0) }
            switch DelayFormat.state(delay) {
            case .unknown:
                EmptyView()
            case .ontime:
                Text("pontos").font(.system(size: size)).foregroundStyle(Theme.ontime)
            case .late, .early:
                let late = DelayFormat.state(delay) == .late
                let min = max(1, Int((Double(abs(delay ?? 0)) / 60).rounded()))
                Text(late ? "+\(min) perc" : "−\(min) perc")
                    .font(Theme.mono(size, weight: .bold))
                    .foregroundStyle(late ? Theme.late : Theme.early)
            }
        }
    }
}

/// Which vehicle is coming: a live plate, or a predicted one (dashed).
private struct KioskVehicle: View {
    let a: KioskArrival
    let size: CGFloat
    let showPredicted: Bool

    var body: some View {
        if a.vehicle != nil {
            HStack(spacing: 0.3 * size) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: size))
                    .foregroundStyle(Theme.live)
                    .accessibilityLabel("élő")
                if let label = a.vehicleLabel {
                    Text(label).font(Theme.mono(size, weight: .bold)).foregroundStyle(Theme.foreground)
                }
            }
        } else if let predicted = a.predictedVehicle, showPredicted, !a.isRail {
            // On a turning loop it is not a guess: the same bus comes back.
            if predicted.method == "loop" {
                Text(TransitModes.displayVehicleId(predicted.id))
                    .font(Theme.mono(size, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .accessibilityHint("Ez a busz fordul vissza a végállomáson")
            } else {
                Text("~\(TransitModes.displayVehicleId(predicted.id))")
                    .font(Theme.mono(size, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 0.35 * size)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0.25 * size, style: .continuous)
                            .strokeBorder(Theme.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    )
                    .accessibilityHint("Előrejelzett rendszám")
            }
        }
    }
}

private struct KioskEta: View {
    let a: KioskArrival
    let em: CGFloat
    var big = false

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !a.isCancelled {
            let mins = max(0, Int(a.etaMin.rounded()))
            if mins <= 0 {
                Text("most")
                    .font(Theme.mono((big ? 1.9 : 1.15) * em, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                    .scaleEffect(pulse ? 0.75 : 1)
                    .opacity(pulse ? 0.4 : 1)
                    .onAppear {
                        guard !reduceMotion else { return }
                        // `live-pulse`: 2.2 s a cycle on the app's ease-out.
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
                    }
            } else {
                let size = (big ? 2.6 : 1.35) * em
                HStack(alignment: .firstTextBaseline, spacing: 0.1 * size) {
                    Text("\(mins)")
                        .font(Theme.mono(size, weight: .heavy))
                        .contentTransition(.numericText())
                    Text("perc")
                        .font(Theme.mono(0.42 * size, weight: .bold))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .fixedSize()
            }
        }
    }
}

private struct KioskFeatured: View {
    let a: KioskArrival
    let em: CGFloat
    let showPredicted: Bool

    var body: some View {
        let where_ = a.progressDesc ?? a.currentStopName.map { "\($0) közelében" }
        let shape = RoundedRectangle(cornerRadius: 0.75 * em, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0.75 * em) {
                KioskTile(a: a, em: em, big: true)
                VStack(alignment: .leading, spacing: 0.3 * em) {
                    Text(a.title)
                        .font(.system(size: 1.1 * em, weight: .bold))
                        .strikethrough(a.isCancelled)
                        .lineLimit(1)
                    HStack(spacing: 0.6 * em) {
                        Text(a.time).font(Theme.mono(0.72 * em, weight: .regular))
                        KioskPlatform(a: a, size: 0.72 * em)
                        KioskDelay(a: a, size: 0.72 * em)
                    }
                    .font(.system(size: 0.72 * em))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                KioskEta(a: a, em: em, big: true)
            }

            if where_ != nil || a.vehicle != nil || a.predictedVehicle != nil {
                HStack(spacing: 0.5 * em) {
                    Image(systemName: a.isRail ? "train.side.front.car" : "bus")
                        .font(.system(size: 0.85 * em))
                    Text(where_ ?? (a.vehicle != nil ? "úton" : "még nem indult el"))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    KioskVehicle(a: a, size: 0.78 * em, showPredicted: showPredicted)
                }
                .font(.system(size: 0.78 * em))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, 0.55 * em)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1) }
                .padding(.top, 0.65 * em)
            }

            if let upper = a.forecastUpperSec, DelayFormat.state(Int(upper)) == .late {
                (Text("Legrosszabb esetben ") + Text(DelayFormat.label(Int(upper))).font(Theme.mono(0.72 * em, weight: .semibold)).foregroundColor(Theme.late))
                    .font(.system(size: 0.72 * em))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.top, 0.45 * em)
            }

            if let notice = a.notices?.first {
                HStack(alignment: .top, spacing: 0.4 * em) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 0.7 * em))
                        .foregroundStyle(Theme.late)
                    Text(notice).lineLimit(1)
                }
                .font(.system(size: 0.7 * em))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, 0.45 * em)
            }
        }
        .padding(.horizontal, 0.9 * em)
        .padding(.vertical, 0.8 * em)
        .background(Theme.muted.opacity(0.4), in: shape)
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
        .opacity(a.isCancelled ? 0.6 : 1)
        .padding(.horizontal, 0.7 * em)
        .padding(.bottom, 0.5 * em)
    }
}

private struct KioskRow: View {
    let a: KioskArrival
    let em: CGFloat
    let showPredicted: Bool

    var body: some View {
        let where_ = a.vehicle != nil ? a.currentStopName : nil
        HStack(spacing: 0.7 * em) {
            KioskTile(a: a, em: em)
            VStack(alignment: .leading, spacing: 0.25 * em) {
                Text(a.title)
                    .font(.system(size: 0.92 * em, weight: .semibold))
                    .strikethrough(a.isCancelled)
                    .lineLimit(1)
                HStack(spacing: 0.55 * em) {
                    Text(a.time).font(Theme.mono(0.66 * em, weight: .regular))
                    KioskPlatform(a: a, size: 0.66 * em)
                    KioskDelay(a: a, size: 0.66 * em)
                    if let where_ { Text("· \(where_)").lineLimit(1) }
                    KioskVehicle(a: a, size: 0.66 * em, showPredicted: showPredicted)
                }
                .font(.system(size: 0.66 * em))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            KioskEta(a: a, em: em)
        }
        .padding(.vertical, 0.62 * em)
        .opacity(a.isCancelled ? 0.6 : 1)
    }
}
