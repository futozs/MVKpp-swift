//
//  RideFixSheet.swift
//  MVK++ Phone App
//
//  Afterwards correction: where the rider got on and off. A loop journey is
//  fixed as a whole — boarding in the first leg, alighting in the last.
//

import SwiftUI

struct RideFixSheet: View {
    enum Mode: Hashable { case from, to }

    let legs: [Ride]
    let initial: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var pickFrom: Int?
    @State private var pickTo: Int?
    @State private var loaded: Loaded = .loading

    private struct Leg: Equatable {
        let stops: [TripStop]
        let times: [Int: RideStopTime]
        let from: Int?
        let to: Int?
    }

    private enum Loaded: Equatable {
        case loading, missing
        case ok([Leg])
    }

    private static let when: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.timeZone = ServiceClock.timeZone
        f.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return f
    }()

    init(legs: [Ride], initial: Mode) {
        self.legs = legs.sorted { $0.boardedAt < $1.boardedAt }
        self.initial = initial
        _mode = State(initialValue: initial)
    }

    private var first: Ride? { legs.first }
    private var last: Ride? { legs.last }
    private var single: Bool { legs.count == 1 }
    private var legA: Leg? { if case .ok(let ls) = loaded { return ls.first } else { return nil } }
    private var legB: Leg? { if case .ok(let ls) = loaded { return ls.count > 1 ? ls[1] : ls.first } else { return nil } }
    private var fromIdx: Int? { pickFrom ?? legA?.from }
    private var toIdx: Int? { pickTo ?? legB?.to }

    private var range: (Int, Int) {
        guard let legA, let legB else { return (0, -1) }
        if mode == .from {
            let end = single ? (toIdx ?? legA.stops.count - 1) : (legA.to ?? legA.stops.count - 1)
            return (0, end - 1)
        }
        let start = single ? (fromIdx ?? 0) : (legB.from ?? 0)
        return (start + 1, legB.stops.count - 1)
    }

    private var changed: Bool {
        (pickFrom != nil && pickFrom != legA?.from) || (pickTo != nil && pickTo != legB?.to)
    }

    var body: some View {
        if let first {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        RouteTile(short: first.route, colorHex: first.color, textHex: first.text, size: .small)
                        Text("Hol szálltál fel és le?").font(Theme.sans(18, weight: .semibold)).tracking(-0.45).foregroundStyle(Theme.foreground)
                    }
                    (Text("\(first.headsign) · \(Self.when.string(from: Date(timeIntervalSince1970: first.boardedAt))) · ") + Text(TransitIds.displayVehicleId(first.vehicleId)).font(Theme.mono(13, weight: .regular)))
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .accessibilityHint(TransitIds.vehicleIdTitle(first.vehicleId))
                }
                .padding(.leading, 20)
                .padding(.trailing, 44)
                .padding(.top, 20)
                .padding(.bottom, 12)

                RideModeTabs(
                    mode: $mode,
                    fromName: fromName ?? "?",
                    toName: toName ?? "?",
                    fromLocked: false
                )
                .padding(.horizontal, 20)

                Group {
                    switch loaded {
                    case .loading:
                        RideMessage(text: "A menet megállóit töltöm…")
                    case .missing:
                        RideMessage(text: "Ennek a menetnek a megállói már nem érhetők el, így most nem javítható.")
                    case .ok:
                        if let leg = mode == .from ? legA : legB {
                            StopChoiceList(
                                stops: leg.stops,
                                lo: range.0,
                                hi: range.1,
                                times: leg.times,
                                timeOf: mode == .from ? .dep : .arr,
                                selected: mode == .from ? fromIdx : toIdx,
                                onPick: { idx in if mode == .from { pickFrom = idx } else { pickTo = idx } }
                            )
                            .id(mode)
                            .padding(.top, 8)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)

                Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1)
                VStack(spacing: 8) {
                    RideButton(title: "Mentés", fullWidth: true, action: save)
                        .disabled(!changed || fromIdx == nil || toIdx == nil)
                    RideButton(title: "Mégse", variant: .ghost, fullWidth: true) { dismiss() }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .presentationDetents([.medium, .large])
            .mvkDialog()
            .task { await load() }
        }
    }

    private var fromName: String? {
        if let legA, let i = fromIdx, legA.stops.indices.contains(i) { return legA.stops[i].name }
        return first?.fromStopName
    }

    private var toName: String? {
        if let legB, let i = toIdx, legB.stops.indices.contains(i) { return legB.stops[i].name }
        return last?.toStopName
    }

    private func load() async {
        guard let first, let last else { return }
        let targets = single ? [first] : [first, last]
        var out: [Leg] = []
        for r in targets {
            guard let d = try? await APIClient.shared.rideTrip(tripId: r.tripId, date: r.serviceDate), let stops = d.stops, !stops.isEmpty else {
                loaded = .missing
                return
            }
            let idx = RideLogic.rideStopIdx(stops, fromStopId: r.fromStopId, toStopId: r.toStopId)
            out.append(Leg(stops: stops, times: RideLogic.stopTimes(d.events ?? []), from: idx.from, to: idx.to))
        }
        loaded = .ok(out)
    }

    private func save() {
        guard let legA, let legB, let fromIdx, let toIdx, let first, let last else { return }
        let board = RideLogic.boardAt(legA.stops, legA.times, fromIdx, .init(
            at: fromIdx == legA.from ? first.boardedAt : nil,
            delayS: fromIdx == legA.from ? (first.delayAtBoardS ?? RideLogic.nearestDelayS(legA.times, fromIdx)) : (RideLogic.nearestDelayS(legA.times, fromIdx) ?? first.delayAtBoardS)
        ))
        let alight = RideLogic.alightAt(legB.stops, legB.times, toIdx, .init(
            at: toIdx == legB.to ? last.alightedAt : nil,
            delayS: toIdx == legB.to ? (last.delayAtAlightS ?? RideLogic.nearestDelayS(legB.times, toIdx)) : (RideLogic.nearestDelayS(legB.times, toIdx) ?? last.delayAtAlightS)
        ))
        guard let board, let alight else { return }
        var boardFix = RideFix(fromStopId: .some(board.fromStopId), fromStopName: .some(board.fromStopName), boardedAt: board.boardedAt, delayAtBoardS: .some(board.delayAtBoardS))
        var alightFix = RideFix(toStopId: .some(alight.toStopId), toStopName: .some(alight.toStopName), alightedAt: .some(alight.alightedAt), delayAtAlightS: .some(alight.delayAtAlightS))
        var fixes: [String: RideFix] = [:]
        if single {
            var fix = boardFix
            fix.toStopId = alightFix.toStopId
            fix.toStopName = alightFix.toStopName
            fix.alightedAt = alightFix.alightedAt
            fix.delayAtAlightS = alightFix.delayAtAlightS
            fix.stops = .some(max(0, toIdx - fromIdx))
            fix.distanceM = .some(RideLogic.pathLengthM(legA.stops, from: fromIdx, to: toIdx))
            fixes[first.id] = fix
        } else {
            let firstEnd = legA.to ?? legA.stops.count - 1
            let lastStart = legB.from ?? 0
            boardFix.stops = .some(max(0, firstEnd - fromIdx))
            boardFix.distanceM = .some(RideLogic.pathLengthM(legA.stops, from: fromIdx, to: firstEnd))
            alightFix.stops = .some(max(0, toIdx - lastStart))
            alightFix.distanceM = .some(RideLogic.pathLengthM(legB.stops, from: lastStart, to: toIdx))
            fixes[first.id] = boardFix
            fixes[last.id] = alightFix
        }
        RideStore.shared.fixRide(legIds: legs.map(\.id), fixes: fixes)
        dismiss()
    }
}

/// „Felszállás” / „Leszállás” tabs with the chosen stop under each.
struct RideModeTabs: View {
    @Binding var mode: RideFixSheet.Mode
    let fromName: String
    let toName: String
    let fromLocked: Bool

    var body: some View {
        HStack(spacing: 8) {
            tab(.from, label: "Felszállás", name: fromName, disabled: fromLocked)
            tab(.to, label: "Leszállás", name: toName, disabled: false)
        }
    }

    private func tab(_ m: RideFixSheet.Mode, label: String, name: String, disabled: Bool) -> some View {
        let on = mode == m
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(Theme.Motion.fastAnimation) { mode = m }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(Theme.sans(10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(on ? Theme.primary : Theme.mutedForeground)
                Text(name)
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(on ? Theme.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).stroke(on ? Theme.primary.opacity(0.6) : Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
