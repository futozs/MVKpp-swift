//
//  RunSummaryView.swift
//  MVK++ Phone App
//

import SwiftUI

/// What actually happened on a run that has started or finished: which
/// vehicle served it, and how far off schedule it began and ended. For a past
/// run the journal is the only record left.
struct RunSummaryView: View {
    let entry: TripJournalEntry

    var body: some View {
        if startText == nil && endText == nil && entry.vehicleId == nil {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 12, lineSpacing: 6) {
                if let vehicleId = entry.vehicleId {
                    HStack(spacing: 6) {
                        Image(systemName: "bus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                        Text(TransitIds.displayVehicleId(vehicleId))
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .accessibilityLabel(TransitIds.vehicleIdTitle(vehicleId))
                        Text("vitte")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    .frame(minHeight: 22)
                }

                if let startText {
                    delayChip(icon: "rectangle.portrait.and.arrow.right", text: startText, sec: entry.startDelaySec)
                }

                if let endText {
                    delayChip(icon: "flag", text: endText, sec: entry.endDelaySec)
                }
            }

            if isPartial, let seen = entry.stopsSeen, let total = entry.stopsTotal {
                Text("Részleges mérés: \(seen)/\(total) megállónál volt élő jel.")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.muted.opacity(0.3))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("A menet tényleges futása")
    }

    private func delayChip(icon: String, text: String, sec: Int?) -> some View {
        let state = DelayFormat.state(sec)
        let border: Color = switch state {
        case .late: Theme.late.opacity(0.4)
        case .early: Theme.early.opacity(0.4)
        case .ontime, .unknown: Theme.border
        }
        let fill: Color = switch state {
        case .late: Theme.late.opacity(0.10)
        case .early: Theme.early.opacity(0.10)
        case .ontime, .unknown: Theme.card
        }
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)

        return HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(Theme.sans(11, weight: .semibold))
        }
        .foregroundStyle(DelayFormat.tone(sec))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(fill, in: shape)
        .overlay(shape.strokeBorder(border, lineWidth: 1))
    }

    private var startText: String? {
        TripStatus.delayPastSentence(entry.startDelaySec, kind: .start)
    }

    private var endText: String? {
        TripStatus.delayPastSentence(entry.endDelaySec, kind: .end)
    }

    private var isPartial: Bool {
        entry.status == "partial" && entry.stopsSeen != nil && entry.stopsTotal != nil
    }
}
