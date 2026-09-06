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
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(etaMin)")
                    .font(.system(size: style == .hero ? 30 : 18, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                Text("perc")
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedForeground)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }
}
