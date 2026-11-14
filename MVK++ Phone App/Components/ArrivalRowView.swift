//
//  ArrivalRowView.swift
//  MVK++ Phone App
//

import SwiftUI

/// One upcoming departure in a board list — the rows of the web app's
/// `StopCard` (`.card`) and `StopDetailDrawer` (`.drawer`). Only a run the
/// feed can locate opens on the map.
struct ArrivalRowView: View {
    enum Variant { case card, drawer }

    let arrival: ArrivalItem
    var onFocusTrip: ((String, String?) -> Void)?
    var variant: Variant = .drawer
    /// The whole list, for finding what runs instead of a cancelled one.
    var list: [ArrivalItem] = []
    var verdict: CatchBus.Verdict?

    @ObservedObject private var features = WatchFeatures.shared

    init(
        arrival: ArrivalItem,
        variant: Variant = .drawer,
        list: [ArrivalItem] = [],
        verdict: CatchBus.Verdict? = nil,
        onFocusTrip: ((String, String?) -> Void)? = nil
    ) {
        self.arrival = arrival
        self.variant = variant
        self.list = list
        self.verdict = verdict
        self.onFocusTrip = onFocusTrip
    }

    var body: some View {
        if let onFocusTrip, arrival.isFocusable {
            Button {
                onFocusTrip(arrival.tripId, arrival.vehicle?.id)
            } label: { content }
            .buttonStyle(RowHighlightStyle())
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: variant == .card ? 12 : 10) {
            RouteTile(short: arrival.tileText, colorHex: arrival.color, textHex: arrival.text)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(arrival.title)
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    if variant == .drawer, arrival.live, !arrival.isCancelled || arrival.vehicle != nil {
                        LiveDot()
                    }
                }

                detailLine

                if insightsVisible {
                    HStack(spacing: 10) {
                        if features.isOn(.startRisk) { StartRiskLine(risk: arrival.startRisk, compact: true) }
                        if features.isOn(.traffic) { TrafficLine(traffic: arrival.trafficAhead, compact: true) }
                    }
                }

                if let progress = arrival.progressDesc {
                    Text(progress)
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }

                NoticeList(notices: arrival.notices, compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            etaBadge
        }
        .padding(.horizontal, variant == .card ? 16 : 12)
        .padding(.vertical, variant == .card ? 10 : 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var insightsVisible: Bool {
        (features.isOn(.startRisk) && arrival.startRisk != nil) || (features.isOn(.traffic) && arrival.trafficAhead != nil)
    }

    private var detailLine: some View {
        HStack(spacing: 8) {
            PlatformBadge(
                platform: arrival.platform,
                changed: arrival.platformChanged == true,
                predicted: arrival.platformPredicted == true,
                mode: arrival.mode,
                compact: true
            )

            if let label = arrival.vehicleLabel {
                VehicleIdChip(text: label)
            } else if variant == .card, let predicted = arrival.predictedVehicle,
                      features.isOn(.predictedVehicle), !arrival.isCancelled, arrival.mode != .rail {
                PredictedVehicleTag(predicted: predicted)
            }

            if variant == .card, arrival.isCancelled { CancelledTag() }

            Text(arrival.time)
                .font(Theme.mono(11, weight: .regular))
                .foregroundStyle(Theme.mutedForeground)
                .strikethrough(arrival.isCancelled, color: Theme.destructive.opacity(0.7))
                .fixedSize()

            if arrival.isCancelled {
                if variant == .drawer {
                    Text("törölve")
                        .font(Theme.sans(10.5, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(Theme.destructive)
                }
                if features.isOn(.replacement) {
                    ReplacementNote(instead: Replacement.instead(of: arrival, in: list), cancelled: arrival, compact: true)
                }
            } else {
                DelayBar(
                    delaySec: variant == .card
                        ? arrival.delaySec ?? arrival.measuredDelaySec
                        : arrival.measuredDelaySec ?? arrival.delaySec,
                    showLabel: false
                )
            }

            if features.isOn(.leaveTimes) { CatchPill(verdict: verdict) }
        }
    }

    @ViewBuilder
    private var etaBadge: some View {
        let size: CGFloat = variant == .card ? 16 : 14
        Group {
            if arrival.isCancelled && variant == .card {
                Text("nem jön")
                    .font(Theme.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.destructive)
            } else if arrival.etaMin <= 0 {
                Text("most")
                    .font(Theme.mono(size))
                    .foregroundStyle(Theme.live)
            } else {
                let parts = Countdown.parts(minutes: arrival.etaMin, hours: false)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(parts.value)
                        .font(Theme.mono(size))
                        .foregroundStyle(Theme.foreground)
                    Text(parts.unit == "perc" ? "p" : parts.unit)
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .strikethrough(arrival.isCancelled && variant == .drawer)
        .opacity(arrival.isCancelled && variant == .drawer ? 0.4 : 1)
        .fixedSize()
    }

    private var accessibilityText: String {
        let eta = arrival.isCancelled ? "törölve" : arrival.etaMin <= 0 ? "most érkezik" : Countdown.spoken(minutes: arrival.etaMin, hours: false)
        let source = arrival.live ? "valós idejű" : "menetrendi"
        return "\(HungarianText.withSuffix(arrival.tileText)), \(arrival.title), \(eta), \(source)"
    }
}

/// The web's `hover:bg-accent` for a tappable list row, shown while pressed.
struct RowHighlightStyle: ButtonStyle {
    /// `hover:bg-accent/45` on the news list.
    var opacity = 1.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.accent.opacity(opacity) : Color.clear)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}
