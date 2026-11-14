//
//  PlannerProofPanel.swift
//  MVK++ Phone App
//

import SwiftUI
import UIKit

/// A past journey summed up in a form that can be shown as proof.
struct PlannerProofPanel: View {
    let plan: JourneyPlanResponse
    let trip: JourneyTrip

    var body: some View {
        let o = PastOutcome(trip)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.rectangle.stack")
                            .font(.system(size: 12, weight: .semibold))
                        Text("IGAZOLÁS")
                            .font(Theme.sans(11, weight: .semibold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Theme.mutedForeground)
                    Text("Bemásolható szöveg, pl. tanárnak vagy munkahelynek.")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                PlannerCopyButton(text: PlannerProof.text(plan: plan, trip: trip))
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Nap") { Text(PlannerFormat.longDate(PlannerFormat.localIsoDate(trip.start))) }
                row("Útvonal") { Text("\(plan.from.name) → \(plan.to.name)") }
                row("Menetrend") {
                    Text("\(PlannerFormat.hm(trip.start)) → \(PlannerFormat.hm(trip.end))").monospacedDigit()
                }
                row("Valójában") {
                    if let arrival = o.actualArrival, let delay = o.arrivalDelayS {
                        Text.joined(
                            Text("érkezés \(PlannerFormat.hms(arrival))\(o.arrivalEstimated ? " (becsült)" : "") · "),
                            Text(PlannerFormat.delayExact(delay)).fontWeight(.semibold).foregroundColor(PlannerFormat.tone(delay).color)
                        )
                        .monospacedDigit()
                    } else {
                        Text("az érkezésről nincs mérés").foregroundStyle(Theme.mutedForeground)
                    }
                }
                row("Járművek") { vehicles }
            }
            .font(Theme.sans(12))
            .foregroundStyle(Theme.foreground)
            .padding(.top, 12)

            if let missed = o.missedTransfer {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .padding(.top, 1)
                    Text("A mért idők szerint az átszállás itt nem jött volna össze: \(missed.at). A tényleges érkezés ennél későbbi lett volna.")
                        .font(Theme.sans(11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.late)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.late.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.late.opacity(0.4), lineWidth: 1))
                .padding(.top, 12)
            }
            if o.partial {
                Text(o.untrackedRoutes.count < o.rideCount
                    ? "Részleges mérés: a(z) \(o.untrackedRoutes.joined(separator: ", ")) menetéről nincs adatunk."
                    : "Erről az útról nincs mérésünk, igazolásra nem alkalmas, csak a menetrendet mutatja.")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .background(Theme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Igazolás")
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.mutedForeground)
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var vehicles: some View {
        let rides = PlannerFormat.transitLegs(trip)
        var parts: [Text] = []
        for (index, leg) in rides.enumerated() {
            if index > 0 { parts.append(Text(", ")) }
            if let id = leg.actual?.vehicleId {
                parts.append(Text(TransitIds.displayVehicleId(id)).font(Theme.mono(12, weight: .semibold)))
            } else {
                parts.append(Text("nincs mérés").foregroundColor(Theme.mutedForeground))
            }
            let route = "\(PlannerFormat.legTileText(leg)) \(leg.trainName ?? PlannerFormat.modeNoun(leg.mode))"
            parts.append(Text(" (\(route))").foregroundColor(Theme.mutedForeground))
        }
        return parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) { Text.joined($0, $1) }
    }
}

private struct PlannerCopyButton: View {
    let text: String

    private enum CopyState { case idle, copied }

    @State private var state = CopyState.idle
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            state = .copied
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .milliseconds(2200))
                guard !Task.isCancelled else { return }
                state = .idle
            }
        } label: {
            Label {
                Text(state == .copied ? "Másolva" : "Másolás")
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: state == .copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(state == .copied ? Theme.ontime : Theme.foreground)
            }
        }
        .buttonStyle(.mvk(.outline, size: .small))
        .sensoryFeedback(.success, trigger: state == .copied) { _, copied in copied }
        .animation(Theme.Motion.fastAnimation, value: state == .copied)
        .accessibilityLabel(state == .copied ? "Másolva" : "Másolás")
    }
}
