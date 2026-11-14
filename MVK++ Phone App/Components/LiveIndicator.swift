//
//  LiveIndicator.swift
//  MVK++ Phone App
//

import SwiftUI

/// The green dot that means "this number is coming from the vehicle right
/// now", so it appears nowhere that shows schedule-only data.
///
/// The web's `LiveDot` stacks a static dot over its `live-pulse` layer, and
/// the pulse only ever shrinks, so the dot reads as steady. Bare
/// `animate-live-pulse` dots elsewhere use `livePulse()`.
struct LiveDot: View {
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Theme.live)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The web's `motion-safe:animate-live-pulse`: 2.2 s per cycle, scale
    /// 0.75 and opacity 0.4 at the midpoint. `scales: false` matches inline
    /// text, where CSS ignores the transform.
    func livePulse(_ active: Bool = true, scales: Bool = true) -> some View {
        modifier(LivePulse(active: active, scales: scales))
    }
}

extension View {
    /// Tailwind's `animate-pulse` (loading states): opacity 1 → 0.5 → 1 over 2 s.
    func loadingPulse(_ active: Bool = true) -> some View {
        modifier(LoadingPulse(active: active))
    }
}

private struct LoadingPulse: ViewModifier {
    let active: Bool

    @State private var low = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(low ? 0.5 : 1)
            .onAppear(perform: update)
            .onChange(of: active, update)
    }

    private func update() {
        if active, !reduceMotion {
            withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 1).repeatForever(autoreverses: true)) { low = true }
        } else {
            withTransaction(Transaction(animation: nil)) { low = false }
        }
    }
}

private struct LivePulse: ViewModifier {
    let active: Bool
    let scales: Bool

    @State private var low = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(scales && low ? 0.75 : 1)
            .opacity(low ? 0.4 : 1)
            .onAppear(perform: update)
            .onChange(of: active, update)
    }

    private func update() {
        if active, !reduceMotion {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1).repeatForever(autoreverses: true)) { low = true }
        } else {
            withTransaction(Transaction(animation: nil)) { low = false }
        }
    }
}

/// Tailwind's `animate-ping`: a copy of the dot grows to 2× and fades out
/// over 0.75 s, once a second.
struct PingRing: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            Circle()
                .fill(color)
                .keyframeAnimator(initialValue: 0.0, repeating: true) { ring, t in
                    ring.scaleEffect(1 + t).opacity(1 - t)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(1, duration: 0.75, timingCurve: .bezier(startControlPoint: UnitPoint(x: 0, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1)))
                        LinearKeyframe(1, duration: 0.25)
                    }
                }
                .accessibilityHidden(true)
        }
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
                    .font(Theme.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.live)
            } else {
                Circle()
                    .fill(Theme.mutedForeground.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text("Menetrendi")
                    .font(Theme.sans(11, weight: .medium))
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
                .font(Theme.sans(compact ? 10 : 11, weight: .semibold))
        }
        .foregroundStyle(Theme.offline)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(
            Theme.offline.opacity(0.14),
            in: Capsule(style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline, menetrend szerinti idők")
    }
}
