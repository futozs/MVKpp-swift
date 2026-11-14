//
//  TripInsights.swift
//  MVK++ Phone App
//

import SwiftUI

/// A departure's predictions on the boards — the web app's
/// `transit/TripInsights`: can I walk there in time, will it start late
/// (its bus is still on the previous run), is there congestion ahead.
enum TripInsightText {
    /// „3 perc”, never „0 perc”.
    static func minutes(_ seconds: Double) -> String {
        "\(max(1, Int((seconds / 60).rounded()))) perc"
    }

    static func catchText(_ verdict: CatchBus.Verdict) -> String {
        switch verdict.state {
        case .relax: return "Ráérsz, indulj \(BudapestClock.hm(verdict.leaveAtUnix))-kor"
        case .go: return "Indulj most"
        case .run: return "Csak futva éred el (\(minutes(verdict.runS)))"
        case .missed: return "Ezt már nem éred el"
        }
    }

    static func tone(_ state: CatchBus.State) -> (fg: Color, bg: Color, border: Color) {
        switch state {
        case .relax: return (Theme.ontime, Theme.ontime.opacity(0.10), Theme.ontime.opacity(0.30))
        case .go: return (Theme.primary, Theme.primary.opacity(0.15), Theme.primary.opacity(0.50))
        case .run: return (TransitTone.amber, TransitTone.amberStrong.opacity(0.12), TransitTone.amberStrong.opacity(0.45))
        case .missed: return (Theme.late, Theme.late.opacity(0.10), Theme.late.opacity(0.40))
        }
    }
}

/// The short catch hint in a list row: leave time, „most”, „fuss” or „lekésed”.
struct CatchPill: View {
    let verdict: CatchBus.Verdict?

    var body: some View {
        if let verdict {
            let tone = TripInsightText.tone(verdict.state)
            let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
            HStack(spacing: 2) {
                Image(systemName: verdict.state == .run ? "bolt.fill" : "figure.walk")
                    .font(.system(size: 8, weight: .bold))
                Text(label(verdict))
                    .font(Theme.mono(10, weight: .bold))
            }
            .foregroundStyle(tone.fg)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(tone.bg, in: shape)
            .overlay(shape.strokeBorder(tone.border, lineWidth: 1))
            .fixedSize()
            .accessibilityLabel("\(TripInsightText.catchText(verdict)) · \(TripInsightText.minutes(verdict.walkS)) séta")
        }
    }

    private func label(_ verdict: CatchBus.Verdict) -> String {
        switch verdict.state {
        case .relax: return BudapestClock.hm(verdict.leaveAtUnix)
        case .go: return "most"
        case .run: return "fuss"
        case .missed: return "lekésed"
        }
    }
}

/// The next departure's „Elérem?” band: the walk, when to leave, and a
/// button to be told when it is time to go (counting the walk).
struct CatchLine: View {
    let verdict: CatchBus.Verdict?
    /// If you miss this one: the next on the same line.
    var next: ArrivalItem?
    var alertOn = false
    var alertBusy = false
    var onToggleAlert: (() -> Void)?

    var body: some View {
        if let verdict {
            let tone = TripInsightText.tone(verdict.state)
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            HStack(spacing: 8) {
                Image(systemName: verdict.state == .run ? "bolt.fill" : "figure.walk")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(TripInsightText.catchText(verdict))\(missedNext(verdict)) \(Text("· \(TripInsightText.minutes(verdict.walkS)) séta").fontWeight(.regular).foregroundStyle(tone.fg.opacity(0.8)))")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onToggleAlert, verdict.state != .missed {
                    Button(action: onToggleAlert) {
                        HStack(spacing: 4) {
                            if alertBusy {
                                ProgressView().controlSize(.mini).tint(tone.fg)
                            } else {
                                Image(systemName: alertOn ? "bell.and.waves.left.and.right.fill" : "bell")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(alertOn ? "Szólok" : "Szólj")
                                .font(Theme.sans(11, weight: .bold))
                                .underline(alertOn, pattern: .dot)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle().inset(by: -8))
                    }
                    .buttonStyle(.plain)
                    .disabled(alertBusy)
                    .accessibilityAddTraits(alertOn ? .isSelected : [])
                    .accessibilityHint(alertOn ? "Szólok, amikor indulni kell. Koppints a kikapcsoláshoz" : "Szólj, amikor indulnom kell (a sétával együtt számolva)")
                }
            }
            .font(Theme.sans(12, weight: .semibold))
            .foregroundStyle(tone.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.bg, in: shape)
            .overlay(shape.strokeBorder(tone.border, lineWidth: 1))
        }
    }

    private func missedNext(_ verdict: CatchBus.Verdict) -> String {
        guard verdict.state == .missed, let next else { return "" }
        return " a következő \(HungarianText.withSuffix(next.route)): \(next.time)"
    }
}

/// The run's bus is still on its previous trip: it will start late or not at all.
struct StartRiskLine: View {
    let risk: ArrivalStartRisk?
    var compact = false

    var body: some View {
        if let risk {
            let missed = risk.level == "likely-missed"
            HStack(alignment: compact ? .center : .top, spacing: compact ? 4 : 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: compact ? 9 : 12, weight: .semibold))
                    .padding(.top, compact ? 0 : 1)
                Text(text(risk, missed: missed))
                    .fixedSize(horizontal: false, vertical: !compact)
                    .lineLimit(compact ? 1 : nil)
            }
            .font(Theme.sans(compact ? 10.5 : 11.5, weight: .semibold))
            .foregroundStyle(missed ? Theme.late : TransitTone.amber)
        }
    }

    private func text(_ risk: ArrivalStartRisk, missed: Bool) -> String {
        if compact {
            return missed ? "valószínűleg kimarad" : "később indul (~\(TripInsightText.minutes(risk.expectedDelayS)))"
        }
        let where_ = risk.prevRoute.map { "még a \(HungarianText.withSuffix($0)) vonalon jár" } ?? "még az előző menetén jár"
        let head = missed
            ? "Valószínűleg kimarad vagy nagyon késve indul"
            : "Várhatóan kb. \(TripInsightText.minutes(risk.expectedDelayS)) késéssel indul"
        return "\(head): a busza (\(risk.predicted ? "~" : "")\(risk.vehicleId)) \(where_), \(BudapestClock.hm(risk.prevEndUnix)) körül ér be."
    }
}

/// Congestion ahead of the bus up to the stop (from the live traffic layer).
struct TrafficLine: View {
    let traffic: ArrivalTrafficAhead?
    var compact = false

    var body: some View {
        if let traffic {
            let heavy = traffic.level >= 0.6
            HStack(alignment: compact ? .center : .top, spacing: compact ? 4 : 6) {
                Image(systemName: "cone.fill")
                    .font(.system(size: compact ? 9 : 12, weight: .semibold))
                    .padding(.top, compact ? 0 : 1)
                Text(compact
                     ? "dugó +\(TripInsightText.minutes(traffic.excessS))"
                     : "Dugó előtte: \(traffic.fromName) → \(traffic.toName), kb. +\(TripInsightText.minutes(traffic.excessS))")
                    .fixedSize(horizontal: false, vertical: !compact)
                    .lineLimit(compact ? 1 : nil)
            }
            .font(Theme.sans(compact ? 10.5 : 11.5, weight: .semibold))
            .foregroundStyle(heavy ? Theme.late : TransitTone.amber)
            .accessibilityHint("\(traffic.fromName) → \(traffic.toName)")
        }
    }
}

enum Replacement {
    /// For a cancelled run: the next non-cancelled departure on the same line
    /// and direction further down the list.
    static func instead(of arrival: ArrivalItem, in list: [ArrivalItem]) -> ArrivalItem? {
        guard arrival.isCancelled, let index = list.firstIndex(of: arrival) else { return nil }
        return list[(index + 1)...].first { !$0.isCancelled && $0.route == arrival.route && $0.headsign == arrival.headsign }
    }
}

/// „helyette 08:05 (+12 perc)” next to a cancelled run.
struct ReplacementNote: View {
    let instead: ArrivalItem?
    let cancelled: ArrivalItem
    var compact = false

    var body: some View {
        if let instead {
            let gap = max(0, instead.etaMin - cancelled.etaMin)
            HStack(spacing: 4) {
                Text("helyette \(instead.time)")
                if gap > 0 {
                    Text("(+\(gap) perc)")
                        .fontWeight(.regular)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .font(Theme.sans(compact ? 10.5 : 11.5, weight: .semibold))
            .foregroundStyle(Theme.ontime)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.ontime.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .fixedSize()
            .padding(.top, compact ? 0 : 8)
        } else if !compact {
            Text("Az MVK kihúzta, a közeli indulások között nincs helyette ugyanilyen.")
                .font(Theme.sans(11.5, weight: .semibold))
                .foregroundStyle(Theme.destructive)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
