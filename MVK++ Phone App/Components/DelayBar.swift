//
//  DelayBar.swift
//  MVK++ Phone App
//

import SwiftUI

/// Schedule deviation as a centre-anchored bar plus its label. The centre line
/// is "on time"; the fill grows right for late and left for early, so lateness
/// is readable at a glance before the number is.
struct DelayBar: View {
    let delaySec: Int?
    var showLabel = true

    private let trackWidth: CGFloat = 48
    private let trackHeight: CGFloat = 4

    var body: some View {
        HStack(spacing: 8) {
            track
            if showLabel {
                Text(DelayFormat.label(delaySec))
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(DelayFormat.tone(delaySec))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Menetrendi eltérés: \(DelayFormat.label(delaySec))")
    }

    private var track: some View {
        let state = DelayFormat.state(delaySec)
        let magnitude = DelayFormat.magnitude(delaySec)
        // Half the track is each direction, so a full-scale delay fills 50%.
        let fillWidth = trackWidth * magnitude * 0.5

        return ZStack(alignment: .center) {
            Capsule()
                .fill(Theme.muted)
                .frame(width: trackWidth, height: trackHeight)

            switch state {
            case .ontime:
                Capsule()
                    .fill(Theme.ontime)
                    .frame(width: 8, height: trackHeight)
            case .late:
                Capsule()
                    .fill(Theme.late)
                    .frame(width: fillWidth, height: trackHeight)
                    .offset(x: fillWidth / 2)
            case .early:
                Capsule()
                    .fill(Theme.early)
                    .frame(width: fillWidth, height: trackHeight)
                    .offset(x: -fillWidth / 2)
            case .unknown:
                EmptyView()
            }
        }
        .frame(width: trackWidth, height: trackHeight)
        .animation(Theme.Motion.normalAnimation, value: delaySec)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        DelayBar(delaySec: nil)
        DelayBar(delaySec: 10)
        DelayBar(delaySec: 240)
        DelayBar(delaySec: -180)
    }
    .padding()
    .background(AppBackground())
}
