//
//  StopRowView.swift
//  MVK++ Watch App
//

import SwiftUI

/// One row on the root list: stop name + its single nearest departure,
/// using the same card design as the stop-detail list.
struct StopRowView: View {
    let stopId: String
    let result: StopArrivalsResponse?
    let isLoading: Bool

    var body: some View {
        if let next = result?.arrivals.first {
            ArrivalCardView(
                route: next.route,
                color: next.color,
                text: next.text,
                delaySec: next.delaySec,
                vehicleId: next.vehicle?.id,
                etaMin: next.etaMin,
                contextLabel: contextLabel
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(contextLabel)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if let result, result.arrivals.isEmpty {
                    Text("Nincs induló járat")
                        .font(.caption2)
                        .foregroundStyle(Theme.mutedForeground)
                } else if isLoading {
                    ProgressView()
                } else {
                    Text("Nincs adat")
                        .font(.caption2)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .glassCard(cornerRadius: 16)
        }
    }

    /// Stop name plus its short numeric code (e.g. "Cementgyár · 84") — needed
    /// when two favorited stops share the same name, so the "SP" id prefix
    /// isn't spelled out, just the number people actually recognize.
    private var contextLabel: String {
        let name = result?.stop.name ?? stopId
        let code = stopId.hasPrefix("SP") ? String(stopId.dropFirst(2)) : stopId
        return "\(name) · \(code)"
    }
}
