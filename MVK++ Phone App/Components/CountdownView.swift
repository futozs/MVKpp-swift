//
//  CountdownView.swift
//  MVK++ Phone App
//

import SwiftUI

/// Time until the vehicle arrives — the largest number on any card, because
/// it is the one thing a rider standing at a stop actually needs.
///
/// At zero it becomes a filled "Most" pill rather than "0 perc": the bus is
/// here, and that is a different message, not a smaller number. Long waits
/// switch to hours (see `Countdown`), which only ever happens on a board read
/// off the downloaded timetable.
struct CountdownView: View {
    enum Size { case medium, large }

    let etaMin: Int
    var size: Size = .large

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if etaMin <= 0 {
                Text("Most")
                    .font(.system(size: size == .large ? 15 : 13, weight: .heavy))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Theme.primaryForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.primary, in: Capsule())
            } else {
                let parts = Countdown.parts(minutes: etaMin)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(parts.value)
                        .font(Theme.mono(size == .large ? 38 : 22))
                        .foregroundStyle(Theme.foreground)
                    Text(parts.unit)
                        .font(.system(size: size == .large ? 13 : 11, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
        .animation(Theme.Motion.normalAnimation, value: etaMin)
        .accessibilityLabel(etaMin <= 0 ? "Beérkezik" : Countdown.spoken(minutes: etaMin))
    }
}
