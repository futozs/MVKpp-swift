//
//  DelayBar.swift
//  MVK++ Phone App
//

import SwiftUI

/// Schedule deviation as a centre-anchored bar plus its label — the web app's
/// `transit/DelayBar`. The centre is "on time"; the fill grows right for late
/// and left for early, half the track at six minutes.
struct DelayBar: View {
    let delaySec: Int?
    var showLabel = true

    private let trackWidth: CGFloat = 48
    private let trackHeight: CGFloat = 4

    var body: some View {
        HStack(spacing: 8) {
            track
            if showLabel, DelayFormat.state(delaySec) != .unknown {
                Text(DelayFormat.label(delaySec))
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(DelayFormat.tone(delaySec))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Menetrendi eltérés: \(DelayFormat.state(delaySec) == .unknown ? "" : DelayFormat.label(delaySec))")
    }

    private var track: some View {
        let state = DelayFormat.state(delaySec)
        let fillWidth = trackWidth * DelayFormat.magnitude(delaySec) * 0.5

        return ZStack {
            Capsule().fill(Theme.muted)

            switch state {
            case .ontime:
                Capsule().fill(Theme.ontime).frame(width: 8)
            case .late:
                Capsule().fill(Theme.late).frame(width: fillWidth).offset(x: fillWidth / 2)
            case .early:
                Capsule().fill(Theme.early).frame(width: fillWidth).offset(x: -fillWidth / 2)
            case .unknown:
                EmptyView()
            }
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(Capsule())
    }
}

/// „Ide várhatóan +3 perccel ér, legrosszabb esetben +6 perc” — the expected
/// delay at this stop from the current delay and the last eight weeks, with
/// the 85th-percentile upper bound. The web app's `transit/ForecastLine`.
struct ForecastLine: View {
    enum Mode { case full, worst }

    let delayS: Int?
    var upperS: Int?
    var mode: Mode = .full

    var body: some View {
        switch mode {
        case .worst:
            if let upperS, DelayFormat.state(upperS) == .late {
                Text("Legrosszabb esetben \(Text(DelayFormat.label(upperS)).font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.late))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityHint("A 85%-os felső becslés: ennél ritkán késik többet (a mostani késésből és az elmúlt 8 hét menetidejeiből)")
            }
        case .full:
            if let delayS {
                fullText(delayS)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityHint("Előrejelzés a mostani késésből és az elmúlt 8 hét menetidejeiből (a felső érték 85%-ban nem lesz rosszabb)")
            }
        }
    }

    private func fullText(_ delayS: Int) -> Text {
        let state = DelayFormat.state(delayS)
        let min = max(1, Int((Double(abs(delayS)) / 60).rounded()))
        let main = state == .ontime ? "pontosan" : state == .late ? "+\(min) perccel" : "\(min) perccel korábban"
        let lead = Text(main).fontWeight(.semibold).foregroundStyle(DelayFormat.tone(delayS))
        if let upperS, upperS - delayS >= 60, DelayFormat.state(upperS) == .late {
            let upper = Text(DelayFormat.label(upperS)).font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.late)
            return Text("Ide várhatóan \(lead) ér, legrosszabb esetben \(upper)")
        }
        return Text("Ide várhatóan \(lead) ér")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        DelayBar(delaySec: nil)
        DelayBar(delaySec: 10)
        DelayBar(delaySec: 240)
        DelayBar(delaySec: -180)
        ForecastLine(delayS: 120, upperS: 360)
        ForecastLine(delayS: nil, upperS: 240, mode: .worst)
    }
    .padding()
    .background(AppBackground())
}
