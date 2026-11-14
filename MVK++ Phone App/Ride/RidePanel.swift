//
//  RidePanel.swift
//  MVK++ Phone App
//
//  After boarding: where the bus is, how late it runs and may run, where
//  traffic stands ahead, and when it stops where — to the end of the trip
//  or until the rider gets off. The rider always says where they got on,
//  where they get off and whether they go round (RideSetup); at the chosen
//  stop the ride closes on its own.
//

import SwiftUI

struct RidePanel: View {
    let ride: ActiveRide
    /// The map is following this bus right now.
    let following: Bool
    let onCancel: () -> Void
    let onRefollow: () -> Void

    @ObservedObject private var controller = RideController.shared
    @State private var collapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trip: TripLive? { controller.trip }
    private var words: TransitMode.Words { controller.mode.words }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.mutedForeground.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 6)
            header
            content
        }
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.xxl, topTrailingRadius: Theme.Radius.xxl, style: .continuous)
                .fill(Theme.card)
                .stroke(Theme.border, lineWidth: 1)
                .mvkShadow(Theme.Shadow.xl)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Utazás")
    }

    // MARK: - Header

    private var trainNo: String? {
        guard controller.mode == .rail, let short = trip?.tripShort else { return nil }
        let digits = short.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RouteTile(short: trainNo.map { "\(ride.route) \($0)" } ?? ride.route, colorHex: ride.color, textHex: ride.text, size: .large)
            VStack(alignment: .leading, spacing: 0) {
                if (ride.leg ?? 1) > 1 {
                    RideEyebrow(text: "Körbeutazás · \(ride.leg ?? 1). menet", systemImage: "repeat", size: 10.5)
                        .padding(.bottom, 2)
                }
                Text(ride.headsign)
                    .font(Theme.sans(14, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(TransitIds.displayVehicleId(ride.vehicleId))
                        .font(Theme.mono(12, weight: .bold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.primary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    Text("most").font(Theme.sans(12)).foregroundStyle(Theme.mutedForeground)
                    Text(trip.map { RideFormat.delayLabel($0.delayS) } ?? "…")
                        .font(Theme.mono(12, weight: .semibold))
                        .foregroundStyle(RideFormat.delayTone(trip?.delayS))
                        .contentTransition(.numericText())
                    if let speed = trip?.vehicle?.speed {
                        Text("\(Int((speed * 3.6).rounded())) km/h")
                            .font(Theme.mono(12, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.top, 4)
                if let trip, !controller.needsFrom, controller.setup == nil, ride.turn == nil, trip.stops.indices.contains(controller.fromIdx) {
                    Button {
                        controller.step = .from
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin").font(.system(size: 11))
                            (Text("Felszállás: ") + Text(trip.stops[controller.fromIdx].name).fontWeight(.semibold).foregroundColor(Theme.foreground) + Text(" · \(BudapestClock.hm(ride.boardedAt))"))
                                .lineLimit(1)
                            Image(systemName: "pencil").font(.system(size: 11)).opacity(0.6)
                                .accessibilityLabel("Felszállás helyének módosítása")
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                if !following {
                    iconButton("scope", label: "A \(words.om) a térképen", action: onRefollow)
                }
                if controller.setup == nil {
                    iconButton(collapsed ? "chevron.up" : "chevron.down", label: collapsed ? "Kinyitás" : "Összecsukás") {
                        withAnimation(reduceMotion ? nil : Theme.Motion.normalAnimation) { collapsed.toggle() }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if let trip {
            if let setup = controller.setup {
                hairline
                RideSetupView(step: setup, ride: ride, trip: trip, cur: controller.cur)
                    .frame(maxHeight: 420)
                footer { cancelButton }
            } else if controller.alightPicker {
                hairline
                alightPicker(trip)
            } else {
                riding(trip)
            }
        } else {
            hairline
            Text("A menet megállóit töltöm…")
                .font(Theme.sans(14))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            footer { cancelButton }
        }
    }

    private var hairline: some View {
        Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1)
    }

    private func footer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            hairline
            HStack(spacing: 8) { content() }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    private var cancelButton: some View {
        RideButton(title: "Mégse", systemImage: "xmark", variant: .ghost) {
            controller.cancel()
            onCancel()
        }
        .accessibilityHint("Mégsem ezen a \(words.on) vagyok")
    }

    @ViewBuilder
    private func riding(_ trip: TripLive) -> some View {
        let turn = ride.turn
        let plan = ride.loopPlan

        if controller.awayAsk, turn == nil {
            VStack(alignment: .leading, spacing: 2) {
                Text("Már nem vagy a buszon?").font(Theme.sans(14, weight: .bold)).foregroundStyle(Theme.foreground)
                Text("Percek óta messze vagy tőle. Amíg nem válaszolsz, az utazás megy tovább a kijelölt leszállóhelyig.")
                    .font(Theme.sans(12)).foregroundStyle(Theme.mutedForeground).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    RideButton(title: "Leszálltam", systemImage: "rectangle.portrait.and.arrow.right", size: .small, fullWidth: true, action: controller.awayAlighted)
                    RideButton(title: "Még rajta vagyok", variant: .outline, size: .small, fullWidth: true, action: controller.awayStillOn)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.late.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).stroke(Theme.late.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
        }

        if let turn, let plan {
            TurnCard(turn: turn, plan: plan, cont: controller.cont, onAlight: controller.turnAlight)
        } else if let plan {
            planCard {
                RideEyebrow(text: "Körbeutazás · \(trip.stops.last?.name ?? "")", systemImage: "repeat")
                Text(plan.stopName.map { "Leszállás: \($0)" } ?? "A végállomáson a buszon maradsz")
                    .font(Theme.sans(14, weight: .bold)).foregroundStyle(Theme.foreground).padding(.top, 2)
                Text(plan.stopName != nil ? "a busz következő menetén; ha odaértél, magától lezárom" : "a leszállást a következő menet indulása után adhatod meg")
                    .font(Theme.sans(12)).foregroundStyle(Theme.mutedForeground).padding(.top, 2)
                if let worst = controller.worstTraffic { trafficLine(worst, trip) }
                planActions(onLoop: nil)
            }
        } else if let destIdx = ride.destIdx, trip.stops.indices.contains(destIdx) {
            let dest = trip.stops[destIdx]
            let fc = trip.forecast[destIdx]
            let remaining = max(0, destIdx - trip.passed)
            planCard {
                RideEyebrow(text: "Leszállás", systemImage: "flag.fill")
                Text(dest.name).font(Theme.sans(14, weight: .bold)).foregroundStyle(Theme.foreground).lineLimit(1).padding(.top, 2)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    (Text("várhatóan ") + Text(BudapestClock.hm(dest.schedTs + (fc?.delayS ?? trip.delayS ?? 0))).font(Theme.mono(14, weight: .bold)).foregroundColor(Theme.foreground))
                    if let fc, fc.upperS - fc.delayS >= 60 {
                        Text("legkésőbb ") + Text(BudapestClock.hm(dest.schedTs + fc.upperS)).font(Theme.mono(12, weight: .semibold)).foregroundColor(Theme.late)
                    }
                    Text("még \(remaining) megálló")
                }
                .font(Theme.sans(12))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, 4)
                if let worst = controller.worstTraffic { trafficLine(worst, trip) }
                planActions(onLoop: trip.loopEnd ? { controller.step = .loop } : nil)
            }
        } else if controller.destPending {
            Text("A leszállóhelyet keresem ezen a meneten…")
                .font(Theme.sans(12)).foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }

        if !collapsed, turn == nil {
            hairline
            stopList(trip)
        }

        footer {
            RideButton(title: turn.map { "Leszálltam (\($0.terminusName))" } ?? "Leszálltam", systemImage: "rectangle.portrait.and.arrow.right", fullWidth: true, action: controller.alightNow)
            if turn == nil {
                RideButton(title: "Korábban", systemImage: "arrow.uturn.backward", variant: .ghost) { controller.alightPicker = true }
                    .accessibilityHint("Már korábban leszálltam, kijelölöm, hol")
            }
            cancelButton
        }
    }

    private func planCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).stroke(Theme.primary.opacity(0.35), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    private func planActions(onLoop: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            RideButton(title: "Módosítom", systemImage: "pencil", variant: .outline, size: .small, fullWidth: true, fill: Theme.card) { controller.step = .to }
            if let onLoop {
                RideButton(title: "Körbeutazok", systemImage: "repeat", variant: .outline, size: .small, fullWidth: true, fill: Theme.card, action: onLoop)
            }
        }
        .padding(.top, 8)
    }

    private func trafficLine(_ t: TrafficAhead, _ trip: TripLive) -> some View {
        let a = trip.stops.indices.contains(t.fromIdx) ? trip.stops[t.fromIdx].name : ""
        let b = trip.stops.indices.contains(t.fromIdx + 1) ? trip.stops[t.fromIdx + 1].name : ""
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: "cone.fill")
                .font(.system(size: 12))
                .foregroundStyle(RideFormat.trafficColor(t.level))
                .padding(.top, 1)
            Text("Dugó előtted: \(a) → \(b), kb. ") + Text("+\(RideFormat.minText(t.excessS))").font(Theme.mono(12, weight: .semibold))
        }
        .font(Theme.sans(12))
        .foregroundStyle(Theme.foreground)
        .padding(.top, 6)
    }

    private func stopList(_ trip: TripLive) -> some View {
        let jams = Dictionary(controller.traffic.map { ($0.fromIdx, $0) }, uniquingKeysWith: { a, _ in a })
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(trip.stops, id: \.idx) { s in
                        RideStopRow(stop: s, trip: trip, ride: ride, jam: jams[s.idx - 1]) {
                            controller.pickDest(s.idx)
                        }
                        .id(s.idx)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 320)
            .onAppear { proxy.scrollTo(trip.passed + 1, anchor: .center) }
            .onChange(of: trip.passed) { _, passed in
                withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(passed + 1, anchor: .center) }
            }
        }
    }

    private func alightPicker(_ trip: TripLive) -> some View {
        let lastIdx = trip.stops.count - 1
        let from = controller.fromIdx
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hol szálltál le?").font(Theme.sans(14, weight: .bold)).foregroundStyle(Theme.foreground)
                    Text("\(controller.isAway ? "Úgy látom, már nem vagy a buszon. " : "")Ahol a busz már járt, az érkezése látszik.")
                        .font(Theme.sans(11.5)).foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RideButton(title: "Vissza", variant: .ghost, size: .small) { controller.alightPicker = false }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            StopChoiceList(
                stops: trip.stops,
                lo: min(lastIdx, from + 1),
                hi: max(from + 1, min(controller.cur, lastIdx)),
                times: trip.times,
                timeOf: .arr,
                selected: nil,
                focusIdx: controller.cur,
                focusLabel: "a busz most itt",
                onPick: controller.pickTo
            )
            .frame(maxHeight: 360)
        }
    }
}

/// One stop of the ride's list; a stop ahead can be tapped to get off there.
struct RideStopRow: View {
    let stop: TripStop
    let trip: TripLive
    let ride: ActiveRide
    let jam: TrafficAhead?
    let onPick: () -> Void

    var body: some View {
        let isPassed = stop.idx <= trip.passed
        let isNext = stop.idx == trip.passed + 1
        let fc = trip.forecast[stop.idx]
        let isDest = ride.destIdx == stop.idx
        let isFrom = ride.fromIdx == stop.idx
        let canPick = !isPassed && stop.idx > (ride.fromIdx ?? 0) && !isDest
        let expected = stop.schedTs + (fc?.delayS ?? trip.delayS ?? 0)

        VStack(alignment: .leading, spacing: 0) {
            if let jam {
                HStack(spacing: 6) {
                    Capsule().fill(RideFormat.trafficColor(jam.level)).frame(width: 4, height: 12)
                    Text("dugó · kb. +\(RideFormat.minText(jam.excessS))")
                }
                .font(Theme.sans(10.5, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.leading, 68)
                .padding(.vertical, 2)
            }
            Button(action: onPick) {
                HStack(spacing: 8) {
                    Text(stop.schedTime)
                        .font(Theme.mono(12, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 48, alignment: .leading)
                    ZStack {
                        Circle()
                            .stroke(isPassed ? Theme.mutedForeground : isNext ? Theme.primary : Theme.mutedForeground.opacity(0.6), lineWidth: 2)
                            .background(Circle().fill(isPassed ? Theme.mutedForeground : isNext ? Theme.primary : .clear))
                            .frame(width: 10, height: 10)
                            .livePulse(isNext)
                    }
                    .frame(width: 16)
                    (Text(stop.name).fontWeight(isNext ? .semibold : .regular)
                        + (isDest ? Text("  · itt szállsz le").font(Theme.sans(11, weight: .semibold)).foregroundColor(Theme.primary) : Text(""))
                        + (isFrom ? Text("  · itt szálltál fel").font(Theme.sans(11, weight: .semibold)).foregroundColor(Theme.mutedForeground) : Text("")))
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !isPassed {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(BudapestClock.hm(expected))
                                .font(Theme.mono(12, weight: .regular))
                                .foregroundStyle(RideFormat.delayTone(fc?.delayS ?? trip.delayS))
                            if let fc, fc.upperS - fc.delayS >= 60 {
                                Text("≤ \(BudapestClock.hm(stop.schedTs + fc.upperS))")
                                    .font(Theme.mono(10, weight: .regular))
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                        }
                        .monospacedDigit()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isDest ? Theme.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay {
                    if isDest { RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).stroke(Theme.primary.opacity(0.4), lineWidth: 1) }
                }
                .opacity(isPassed ? 0.45 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .disabled(!canPick)
            .accessibilityHint(canPick ? "Itt szállok le" : "")
        }
    }
}
