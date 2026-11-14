//
//  CountdownView.swift
//  MVK++ Phone App
//

import SwiftUI

/// Time until the vehicle arrives — the web app's `transit/Countdown`. At zero
/// it becomes a filled "Most" tag; each new value drops in from above.
/// Waits past an hour and a half (only ever read off the downloaded
/// timetable) switch to hours, see `Countdown`.
struct CountdownView: View {
    enum Size { case medium, large }

    let etaMin: Int
    var size: Size = .large

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .trailing) {
            value
                .id(etaMin <= 0 ? -1 : etaMin)
                .transition(
                    reduceMotion
                        ? .identity
                        : .asymmetric(
                            insertion: .offset(y: -8).combined(with: .opacity),
                            removal: .identity
                        )
                )
        }
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22), value: etaMin)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etaMin <= 0 ? "Beérkezik" : Countdown.spoken(minutes: etaMin))
    }

    @ViewBuilder
    private var value: some View {
        if etaMin <= 0 {
            Text("Most")
                .font(.system(size: size == .large ? 14 : 12, weight: .heavy))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(Theme.primaryForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        } else {
            let parts = Countdown.parts(minutes: etaMin)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.value)
                    .font(Theme.mono(size == .large ? 32 : 20))
                    .foregroundStyle(Theme.foreground)
                Text(parts.unit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
    }
}
