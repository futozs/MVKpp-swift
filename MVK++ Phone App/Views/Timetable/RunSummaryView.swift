//
//  RunSummaryView.swift
//  MVK++ Phone App
//

import SwiftUI

/// What actually happened on a run that has already started or finished:
/// which vehicle served it, and how far off schedule it began and ended.
///
/// The live feed drops a run the moment it completes, so for anything in the
/// past this journal is the only record — and "which bus was that?" is exactly
/// what a rider wants to know afterwards.
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
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 10, lineSpacing: 6) {
                if let vehicleId = entry.vehicleId {
                    HStack(spacing: 5) {
                        Image(systemName: "bus")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.mutedForeground)
                        Text(vehicleId).font(Theme.mono(11))
                        Text("vitte")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }

                if let startText {
                    delayChip(icon: "arrow.up.forward", text: startText, sec: entry.startDelaySec)
                }

                if let endText {
                    delayChip(icon: "flag.checkered", text: endText, sec: entry.endDelaySec)
                }
            }

            if isPartial, let seen = entry.stopsSeen, let total = entry.stopsTotal {
                Text("Részleges mérés: \(seen)/\(total) megállónál volt élő jel.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.muted.opacity(0.3))
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

        return HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(DelayFormat.tone(sec))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
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
