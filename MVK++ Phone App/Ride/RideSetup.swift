//
//  RideSetup.swift
//  MVK++ Phone App
//
//  On boarding the rider always says where they got on, where they will get
//  off and — at a turning loop terminus — whether they go round. No guessing:
//  at the chosen stop the app closes the ride itself, phone in a pocket too.
//

import SwiftUI

struct RideSetupView: View {
    let step: RideSetupStep
    let ride: ActiveRide
    let trip: TripLive
    /// Where the bus is now.
    let cur: Int

    @ObservedObject private var controller = RideController.shared

    private var lastIdx: Int { trip.stops.count - 1 }
    private var fromIdx: Int { ride.fromIdx ?? 0 }
    private var terminus: String { trip.stops.last?.name ?? "végállomás" }
    /// The setup is done (it can be closed) only when nothing is missing.
    private var canClose: Bool { !controller.needsFrom && !controller.needsDest }

    var body: some View {
        switch step {
        case .from: fromStep
        case .to: toStep
        case .loop: RideLoopStep(ride: ride, terminus: terminus, onBack: { controller.step = .to }, onLoop: controller.pickLoop)
        }
    }

    private var fromStep: some View {
        VStack(spacing: 0) {
            RideStepHead(
                title: "Hol szálltál fel?",
                hint: "Koppints a megállóra. Ahol a busz már járt, ott az indulása látszik.",
                onBack: canClose && ride.fromConfirmed == true ? { controller.step = nil } : nil
            )
            StopChoiceList(
                stops: trip.stops,
                lo: 0,
                hi: max(0, min(lastIdx - 1, cur + 1, ride.destIdx.map { $0 - 1 } ?? Int.max)),
                times: trip.times,
                timeOf: .dep,
                selected: ride.fromConfirmed == true ? ride.fromIdx : nil,
                focusIdx: cur,
                focusLabel: "a busz most itt",
                onPick: controller.pickFrom
            )
        }
    }

    private var toStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            RideStepHead(
                title: "Hol szállsz le?",
                hint: "Ha a busz odaért, magától lezárom az utazást — akkor is, ha közben nem nyitod meg az appot.",
                onBack: canClose ? { controller.step = nil } : { controller.step = .from }
            )
            Button {
                controller.step = .from
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin").font(.system(size: 11))
                    Text("Felszállás: ") + Text(trip.stops.indices.contains(fromIdx) ? trip.stops[fromIdx].name : "").fontWeight(.semibold).foregroundColor(Theme.foreground)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.mutedForeground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            StopChoiceList(
                stops: trip.stops,
                lo: min(lastIdx, fromIdx + 1),
                hi: lastIdx,
                times: trip.times,
                timeOf: .arr,
                selected: ride.destIdx,
                marks: [lastIdx: "végállomás"],
                onPick: controller.pickDest
            )
            if trip.loopEnd {
                Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1)
                Button {
                    controller.step = .loop
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "repeat").foregroundStyle(Theme.primary)
                        Text("Körbeutazok — \(terminus)-nál a buszon maradok").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 38)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(Theme.primary.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(RidePressStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

/// Loop journey planned ahead: where to get off on the bus's next trip.
struct RideLoopStep: View {
    let ride: ActiveRide
    let terminus: String
    let onBack: () -> Void
    let onLoop: (LoopPlan) -> Void

    private struct NextTrip: Equatable {
        let tripId: String
        let route: String
        let color: String
        let text: String
        let headsign: String
        let depTime: String
        let serviceDate: String
    }

    private enum Loaded: Equatable {
        case loading
        case none
        case failed
        case ok(NextTrip, [TripStop], [Int: RideStopTime])
    }

    @State private var loaded: Loaded = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RideStepHead(
                title: "Körbeutazás: hol szállsz le?",
                hint: "\(terminus)-nál a buszon maradsz. Válaszd ki, hol szállsz le a következő menetéből — odáig magától viszem tovább az utazást.",
                onBack: onBack
            )
            switch loaded {
            case .loading:
                RideMessage(text: "Megnézem, merre megy tovább a busz…")
            case .none, .failed:
                fallback
            case .ok(let next, let stops, let times):
                nextHeader(next)
                if stops.isEmpty {
                    fallback
                } else {
                    let selected = ride.loopPlan?.stopId.flatMap { id in stops.indices.first { $0 > 0 && stops[$0].id == id } }
                    StopChoiceList(
                        stops: stops,
                        lo: 1,
                        hi: stops.count - 1,
                        times: times,
                        timeOf: .arr,
                        selected: selected,
                        marks: [stops.count - 1: "végállomás"],
                        onPick: { idx in onLoop(LoopPlan(stopId: stops[idx].id, stopName: stops[idx].name, tripId: next.tripId)) }
                    )
                }
            }
        }
        .task(id: "\(ride.tripId)|\(ride.vehicleId)|\(ride.serviceDate)") { await load() }
    }

    private var fallback: some View {
        VStack(spacing: 12) {
            Text("Még nem látom, melyik menettel megy tovább a busz.")
                .font(.system(size: 14)).foregroundStyle(Theme.mutedForeground).multilineTextAlignment(.center)
            RideButton(title: "Körbeutazok, a leszállást később adom meg", systemImage: "repeat") {
                onLoop(LoopPlan(stopId: nil, stopName: nil, tripId: nil))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }

    private func nextHeader(_ next: NextTrip) -> some View {
        HStack(spacing: 8) {
            RouteTile(short: next.route, colorHex: next.color, textHex: next.text, size: .small)
            (Text("\(next.headsign) · indul ") + Text(next.depTime).font(Theme.mono(12, weight: .semibold)).foregroundColor(Theme.foreground))
                .lineLimit(1)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.mutedForeground)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func load() async {
        loaded = .loading
        var next: NextTrip?
        if let c = try? await APIClient.shared.continuation(tripId: ride.tripId, vehicleId: ride.vehicleId), let n = c.next, n.kind != nil, !n.cancelled {
            next = NextTrip(tripId: n.tripId, route: n.route, color: n.color, text: n.text, headsign: n.headsign, depTime: n.depTime, serviceDate: ride.serviceDate)
        } else if let choices = try? await APIClient.shared.rideLogNext(serviceDate: ride.serviceDate, tripId: ride.tripId, vehicleId: ride.vehicleId),
                  let pick = choices.first(where: { $0.sameVehicle == true }) ?? choices.first(where: { $0.kind == "loop" }) ?? choices.first {
            next = NextTrip(tripId: pick.tripId, route: pick.route, color: pick.color, text: pick.text, headsign: pick.headsign, depTime: BudapestClock.hm(pick.depTs), serviceDate: pick.serviceDate)
        }
        guard let next else {
            loaded = .none
            return
        }
        guard let detail = try? await APIClient.shared.rideTrip(tripId: next.tripId, date: next.serviceDate) else {
            loaded = .failed
            return
        }
        loaded = .ok(next, detail.stops ?? [], RideLogic.stopTimes(detail.events ?? []))
    }
}

/// Loop journey at the terminus: the rider said they stay on. As soon as the
/// bus leaves on its next trip the ride carries on with it — phone locked too.
struct TurnCard: View {
    let turn: RideTurn
    let plan: LoopPlan
    let cont: Continuation?
    let onAlight: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            let now = RealtimeClient.shared.serverNow.rounded()
            let next = cont?.next
            let late = next.map { max(0, now - $0.depTs) } ?? 0
            VStack(alignment: .leading, spacing: 0) {
                RideEyebrow(text: "Körbeutazás · \(turn.terminusName)", systemImage: "repeat")
                Text("Beért \(BudapestClock.hm(turn.arrivedAt))-kor. \(next != nil ? "Maradj ülve — a busz innen így megy tovább:" : "Keresem, mikor és merre indul tovább a busz…")")
                    .font(.system(size: 12)).foregroundStyle(Theme.mutedForeground).padding(.top, 2)
                if let next {
                    HStack(spacing: 10) {
                        RouteTile(short: next.route, colorHex: next.color, textHex: next.text)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(next.headsign).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.foreground).lineLimit(1)
                            (Text("indul ") + Text(next.depTime).font(Theme.mono(12, weight: .bold)).foregroundColor(Theme.foreground)
                                + Text(" · \(next.departed ? "elindult" : late > 60 ? "\(Int((late / 60).rounded())) perce esedékes" : Self.inLabel(next.depTs - now))")
                                + Text(next.kind == "nearby" ? " · a szomszédos kocsiállásból (\(next.firstStopName))" : "")
                                + Text(next.cancelled ? " · törölték" : ""))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 8)
                }
                Group {
                    if let name = plan.stopName {
                        Text("Leszállás: ") + Text(name).fontWeight(.semibold).foregroundColor(Theme.foreground) + Text(" — ha odaértél, magától lezárom.")
                    } else {
                        Text("Ha a busz elindul, kiválaszthatod, hol szállsz le.")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, 8)
                RideButton(title: "Mégis itt szálltam le", systemImage: "rectangle.portrait.and.arrow.right", variant: .outline, size: .small, fullWidth: true, action: onAlight)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).stroke(Theme.primary.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private static func inLabel(_ sec: Double) -> String {
        sec <= 30 ? "most indul" : "\(Int((sec / 60).rounded())) perc múlva"
    }
}
