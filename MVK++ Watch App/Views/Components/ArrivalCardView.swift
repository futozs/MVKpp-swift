//
//  ArrivalCardView.swift
//  MVK++ Watch App
//

import SwiftUI

/// The one arrival card design used everywhere — the root list (with a
/// `contextLabel` stop name above it) and the stop-detail list (without).
/// Just the essentials: route number, ETA, vehicle ID, delay — no headsign,
/// which turned out not to be worth the space it took.
struct ArrivalCardView: View {
    let route: String
    let color: String
    let text: String
    let delaySec: Int?
    let vehicleId: String?
    let etaMin: Int
    var contextLabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let contextLabel {
                Text(contextLabel)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                RouteTile(short: route, colorHex: color, textHex: text, size: .large)
                Spacer(minLength: 4)
                CountdownView(etaMin: etaMin, style: .hero)
            }

            HStack(spacing: 8) {
                if let vehicleId {
                    Text("#\(vehicleId)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                DelayIndicator(delaySec: delaySec)
            }
        }
        .glassCard(cornerRadius: 16)
    }
}
