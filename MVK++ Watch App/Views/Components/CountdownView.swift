//
//  CountdownView.swift
//  MVK++ Watch App
//

import SwiftUI

/// Minutes-to-arrival readout. Shows a "MOST" (now) pill at zero, otherwise a
/// large tabular-figure number — mirrors the web app's Countdown component.
struct CountdownView: View {
    enum Style { case hero, compact }

    let etaMin: Int
    var style: Style = .compact

    var body: some View {
        if etaMin <= 0 {
            Text("MOST")
                .font(style == .hero ? .callout : .caption2)
                .fontWeight(.heavy)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, style == .hero ? 10 : 6)
                .padding(.vertical, style == .hero ? 4 : 2)
                .background(Theme.primary)
                .foregroundStyle(.black)
                .clipShape(Capsule())
        } else {
            let parts = Countdown.parts(minutes: etaMin)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.value)
                    .font(.system(size: style == .hero ? 26 : 16, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                Text(style == .hero || parts.unit != "perc" ? parts.unit : "p")
                    .font(.system(size: style == .hero ? 11 : 10, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }
}
