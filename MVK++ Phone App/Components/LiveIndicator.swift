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

/// Shown when the board is coming off the downloaded timetable because the
/// gateway could not be reached.
///
/// "Menetrendi" already means "no vehicle is reporting"; this is the stronger
/// statement that nothing is reporting at all, so a rider knows a delay would
/// not be shown even if there were one.
struct OfflineTag: View {
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(compact ? "Offline" : "Offline · menetrend szerint")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
        }
        .foregroundStyle(Theme.offline)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(
            Theme.offline.opacity(0.14),
            in: Capsule(style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline — menetrend szerinti idők")
    }
}
