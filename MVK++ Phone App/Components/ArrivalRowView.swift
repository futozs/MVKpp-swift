//
//  ArrivalRowView.swift
//  MVK++ Phone App
//

import SwiftUI

/// One upcoming departure. Used by both the stop sheet and the watchlist
/// cards, so a departure looks the same wherever the rider meets it.
///
/// Only rows backed by a live vehicle are tappable — following a run the feed
/// cannot locate would open an empty map.
struct ArrivalRowView: View {
    let arrival: ArrivalItem
    var onFocusTrip: ((String, String?) -> Void)?

    private var isFocusable: Bool {
        onFocusTrip != nil && arrival.live && !arrival.tripId.isEmpty
    }

    var body: some View {
        Group {
            if isFocusable {
                Button {
                    onFocusTrip?(arrival.tripId, arrival.vehicle?.id)
                } label: { content }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            RouteTile(short: arrival.route, colorHex: arrival.color, textHex: arrival.text)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(arrival.headsign)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    if arrival.live { LiveDot(size: 7) }
                }

                HStack(spacing: 8) {
                    if let vehicle = arrival.vehicle {
                        Text(vehicle.id)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Theme.primary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                    }
                    Text(arrival.time)
                        .font(Theme.mono(11, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                    DelayBar(delaySec: arrival.delaySec, showLabel: false)
                }

                if let progress = arrival.progressDesc {
                    Text(progress)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            etaBadge
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var etaBadge: some View {
        if arrival.etaMin <= 0 {
            Text("most")
                .font(Theme.mono(14))
                .foregroundStyle(Theme.live)
        } else {
            let parts = Countdown.parts(minutes: arrival.etaMin)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(parts.value)
                    .font(Theme.mono(16))
                    .foregroundStyle(Theme.foreground)
                Text(parts.unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
    }

    private var accessibilityText: String {
        let eta = arrival.etaMin <= 0 ? "most érkezik" : Countdown.spoken(minutes: arrival.etaMin)
        let source = arrival.live ? "valós idejű" : "menetrendi"
        return "\(HungarianText.withSuffix(arrival.route)), \(arrival.headsign), \(eta), \(source)"
    }
}
