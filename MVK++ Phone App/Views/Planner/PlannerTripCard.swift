//
//  PlannerTripCard.swift
//  MVK++ Phone App
//

import SwiftUI

struct PlannerTripCard: View {
    let plan: JourneyPlanResponse
    let trip: JourneyTrip
    @State private var isOpen: Bool

    /// This much slip still counts as making the "arrive by" target.
    private static let arriveBySlackSec: Double = 59

    init(plan: JourneyPlanResponse, trip: JourneyTrip, defaultOpen: Bool) {
        self.plan = plan
        self.trip = trip
        _isOpen = State(initialValue: defaultOpen)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Theme.Motion.normalAnimation) { isOpen.toggle() }
            } label: {
                header
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOpen ? "kinyitva" : "becsukva")

            if isOpen {
                VStack(alignment: .leading, spacing: 16) {
                    PlannerTripTimeline(trip: trip, mode: plan.mode)
                    if plan.mode == .past {
                        PlannerProofPanel(plan: plan, trip: trip)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(shape)
        .background(Theme.card, in: shape)
        .overlay(shape.strokeBorder(isOpen ? Theme.primary.opacity(0.35) : Theme.border, lineWidth: 1))
        .modifier(OpenShadow(isOpen: isOpen))
        .sensoryFeedback(.selection, trigger: isOpen)
    }

    private var header: some View {
        let worst = PlannerForecast.worstTransfer(trip)
        let worstMeasured = worst.map { plan.mode != .past || PastOutcome.transferMeasured(trip, index: $0.index) } ?? false
        let showWorst = worst.map { $0.check.risk != .safe && worstMeasured } ?? false
        let walk = PlannerFormat.walkTotalSec(trip)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(PlannerFormat.hm(trip.start))
                    Text("→")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                    Text(PlannerFormat.hm(trip.end))
                }
                .font(Theme.mono(18, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Theme.foreground)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text(PlannerFormat.minutes(trip.durationSec))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
            }

            HStack(alignment: .center, spacing: 8) {
                PlannerRouteChain(trip: trip)
                Spacer(minLength: 0)
                Text(PlannerFormat.transfersLabel(trip.transfers) + (walk >= 60 ? " · \(PlannerFormat.minutes(walk)) gyalog" : ""))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
            }

            if plan.mode == .past {
                PlannerPastStatus(trip: trip)
            } else {
                PlannerForecastStatus(trip: trip)
            }
            if plan.mode != .past && plan.arriveBy {
                arriveByWarning
            }
            if showWorst, let worst {
                PlannerTransferBadge(check: worst.check, mode: plan.mode, measured: worstMeasured)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var arriveByWarning: some View {
        let f = TripForecast(trip)
        let target = plan.at
        let expectedLate = f.expectedArrival.map { $0 > target + Self.arriveBySlackSec } ?? false
        let worstLate = f.worstArrival.map { $0 > target + Self.arriveBySlackSec } ?? false
        if expectedLate || worstLate {
            Text(expectedLate
                ? "\(PlannerFormat.hm(target))-ig várhatóan nem érsz be válassz korábbi indulást."
                : "Rossz esetben \(PlannerFormat.hm(target)) után érsz be.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(expectedLate ? Theme.late : PlannerAmber.a300)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OpenShadow: ViewModifier {
    let isOpen: Bool

    func body(content: Content) -> some View {
        if isOpen {
            content.mvkShadow(Theme.Shadow.md)
        } else {
            content
        }
    }
}

private struct PlannerRouteChain: View {
    let trip: JourneyTrip

    var body: some View {
        let rides = PlannerFormat.transitLegs(trip)
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(Array(rides.enumerated()), id: \.offset) { index, leg in
                HStack(spacing: 4) {
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    RouteTile(short: PlannerFormat.legTileText(leg), colorHex: leg.routeColor ?? "1FB574", textHex: leg.routeTextColor, size: .small)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PlannerPastStatus: View {
    let trip: JourneyTrip

    var body: some View {
        let o = PastOutcome(trip)
        let tone: PlannerFormat.Tone = o.missedTransfer != nil ? .late : PlannerFormat.tone(o.arrivalDelayS)
        let lastDep = PlannerFormat.transitLegs(trip).last?.actual?.depDelayS
        let detail: String? = {
            if o.missedTransfer != nil { return nil }
            if let arrival = o.actualArrival {
                return "(\(o.arrivalEstimated ? "becsült érkezés" : "valójában") \(PlannerFormat.hms(arrival)))"
            }
            if let lastDep { return "(az utolsó járat \(PlannerFormat.delayShort(lastDep)) eltéréssel indult)" }
            return nil
        }()
        FlowLayout(spacing: 6, lineSpacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Text(o.headline)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(tone.color)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.mutedForeground)
            }
            if o.partial && o.untrackedRoutes.count < o.rideCount {
                Text("· részleges mérés")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
    }
}

private struct PlannerForecastStatus: View {
    let trip: JourneyTrip

    var body: some View {
        let f = TripForecast(trip)
        if let expected = f.expectedArrival, let delay = f.arrDelayS {
            FlowLayout(spacing: 6, lineSpacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                    Text.joined(
                        Text("Várható érkezés "),
                        Text(PlannerFormat.hm(expected)).fontWeight(.semibold).monospacedDigit(),
                        Text(" (\(PlannerFormat.delayForecast(delay)))").fontWeight(.semibold).foregroundColor(PlannerFormat.tone(delay).color),
                        Text(f.worstArrival != nil ? "," : "").foregroundColor(Theme.mutedForeground)
                    )
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.foreground)
                }
                if let worst = f.worstArrival {
                    Text.joined(
                        Text("rossz esetben ").foregroundColor(Theme.mutedForeground),
                        Text(PlannerFormat.hm(worst)).fontWeight(.semibold).monospacedDigit().foregroundColor(Theme.foreground)
                    )
                        .font(.system(size: 12))
                }
            }
        } else {
            Text("Nincs késési adat a menetrend szerinti időket mutatjuk.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How safe a transfer is: measured for a past day, the odds today and later.
struct PlannerTransferBadge: View {
    let check: JourneyTransferCheck
    let mode: JourneyMode
    /// In the past: both sides were measured. If not, the margin is the timetable's.
    var measured = true

    private enum Kind { case safe, tight, risky, unknown }

    var body: some View {
        let kind = self.kind
        let (label, title) = copy
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon(kind))
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(foreground(kind))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background(kind), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(border(kind), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint(title)
    }

    private var kind: Kind {
        if mode == .past && !measured { return .unknown }
        switch check.risk {
        case .safe: return .safe
        case .tight: return .tight
        case .risky: return .risky
        }
    }

    private func icon(_ kind: Kind) -> String {
        switch kind {
        case .safe: return "checkmark.circle"
        case .tight: return "exclamationmark.triangle"
        case .risky: return "xmark.circle"
        case .unknown: return "circle.dashed"
        }
    }

    private func foreground(_ kind: Kind) -> Color {
        switch kind {
        case .safe: return Theme.ontime
        case .tight: return PlannerAmber.a300
        case .risky: return Theme.late
        case .unknown: return Theme.mutedForeground
        }
    }

    private func background(_ kind: Kind) -> Color {
        switch kind {
        case .safe: return Theme.ontime.opacity(0.10)
        case .tight: return PlannerAmber.a400.opacity(0.10)
        case .risky: return Theme.late.opacity(0.12)
        case .unknown: return Theme.muted.opacity(0.6)
        }
    }

    private func border(_ kind: Kind) -> Color {
        switch kind {
        case .safe: return Theme.ontime.opacity(0.35)
        case .tight: return PlannerAmber.a400.opacity(0.40)
        case .risky: return Theme.late.opacity(0.45)
        case .unknown: return Theme.border
        }
    }

    private var copy: (String, String) {
        let m = PlannerFormat.marginText(check.marginSec)
        if mode == .past {
            if !measured {
                return ("nincs mérés: menetrend szerint \(m) tartalék", "Az átszállás egyik oldaláról nincs mérésünk, ezért a menetrendi tartalékot mutatjuk.")
            }
            let title = "A mért érkezés és a következő járat mért indulása közti idő."
            switch check.risk {
            case .risky: return ("lekésted volna: \(m)-cel", title)
            case .tight: return ("épphogy elérted volna: \(m) tartalék", title)
            case .safe: return ("elérted volna: \(m) tartalék", title)
            }
        }
        if let chance = check.chance {
            let pct = Int((chance * 100).rounded())
            let title = "Az első busz várható és rossz esetbeli érkezéséből, a csatlakozás várható indulásából és a séta idejéből (\(m) \(check.marginSec < 0 ? "hiány" : "tartalék") várhatóan)."
            let alt = check.fallback.map { " · ha lekésed: \($0.time)" } ?? ""
            switch check.risk {
            case .risky: return ("\(pct)% esély valószínűleg lekésed\(alt)", title)
            case .tight: return ("\(pct)% eséllyel eléred\(alt)", title)
            case .safe: return ("\(pct)% eséllyel eléred · \(m) tartalék", title)
            }
        }
        let title = "A következő járat várható indulása és az előző rossz esetben (85%) várható érkezése közti idő."
        switch check.risk {
        case .risky: return ("kockázatos: valószínűleg lekésed", "\(title) Rossz esetben \(m) hiányzik.")
        case .tight: return ("szoros: \(m) tartalék", title)
        case .safe: return ("kényelmes: \(m) tartalék", title)
        }
    }
}

/// „Figyeld az átszállást”: if the odds collapse on the way (the first bus
/// runs late, the connection leaves early) the rider is told, with the next option.
struct PlannerTransferWatchButton: View {
    let check: JourneyTransferCheck

    @ObservedObject private var alerts = TransferAlertStore.shared
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        if check.toTripId != nil, check.fromTripId != nil, check.boardStopId != nil, check.alightStopId != nil {
            let on = alerts.isOn(check)
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    Task { await toggle(on: on) }
                } label: {
                    HStack(spacing: 4) {
                        if busy {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(on ? Theme.primaryForeground : Theme.mutedForeground)
                        } else {
                            Image(systemName: on ? "bell.and.waves.left.and.right" : "bell.badge")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(on ? "Figyelem az átszállást" : "Figyeld az átszállást")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(on ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(on ? Theme.primary : Theme.border, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlannerPressStyle())
                .disabled(busy)
                .sensoryFeedback(.success, trigger: on) { _, now in now }
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityHint(on ? "Szólok, ha veszélybe kerül az átszállás koppints a kikapcsoláshoz" : "Szólj, ha veszélybe kerül ez az átszállás")

                if let note {
                    Text(note)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func toggle(on: Bool) async {
        busy = true
        note = nil
        defer { busy = false }
        if on {
            alerts.remove(check)
            return
        }
        let result = await alerts.add(check)
        note = result.ok ? TransferAlertStore.noPushNote : (result.reason ?? "Nem sikerült bekapcsolni.")
    }
}
