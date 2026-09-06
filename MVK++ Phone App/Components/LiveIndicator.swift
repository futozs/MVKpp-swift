//
//  LiveIndicator.swift
//  MVK++ Phone App
//

import SwiftUI

/// The pulsing green dot. This is the app's only ambient motion — it means
/// "this number is coming from the vehicle right now", so it appears nowhere
/// that shows schedule-only data.
struct LiveDot: View {
    var size: CGFloat = 8

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.live)
                .scaleEffect(pulsing ? 0.75 : 1)
                .opacity(pulsing ? 0.4 : 1)
            Circle()
                .fill(Theme.live)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// The provenance label for a departure: real-time or timetable-only. Riders
/// need to know which one they are looking at before they decide to run.
struct LiveTag: View {
    let live: Bool

    var body: some View {
        HStack(spacing: 6) {
            if live {
                LiveDot()
                Text("Valós idejű")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.live)
            } else {
                Circle()
                    .fill(Theme.mutedForeground.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text("Menetrendi")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(live ? "Valós idejű adat" : "Menetrendi adat")
    }
}
