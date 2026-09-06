//
//  DelayIndicator.swift
//  MVK++ Watch App
//

import SwiftUI

/// Just the signed delay, e.g. "+4" or "-1" — the sign alone says late vs.
/// early, so no unit or word is spelled out. `nil` delaySec means no live
/// data at all, shown as "—".
struct DelayIndicator: View {
    let delaySec: Int?

    private let thresholdSec = 45

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var label: String {
        guard let delaySec else { return "—" }
        if abs(delaySec) < thresholdSec { return "0" }
        let minutes = Int((Double(abs(delaySec)) / 60).rounded())
        return delaySec > 0 ? "+\(minutes)" : "-\(minutes)"
    }

    private var color: Color {
        guard let delaySec else { return Theme.mutedForeground }
        if abs(delaySec) < thresholdSec { return Theme.ontime }
        return delaySec > 0 ? Theme.late : Theme.early
    }
}
