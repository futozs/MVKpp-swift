//
//  TripPlanCard.swift
//  MVK++ Phone App
//

import SwiftUI

/// One itinerary: when to leave, what to board, where to change.
///
/// Each boarding carries a punctuality note from our own measurements — the
/// operator's planner only ever quotes the timetable, and knowing that a
/// particular boarding is habitually four minutes late changes the decision.
struct TripPlanCard: View {
    let trip: RoutePlanTrip
    @ObservedObject var model: RoutePlannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(RoutePlannerModel.hourMinute(trip.start)) → \(RoutePlannerModel.hourMinute(trip.end))")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.foreground)

                Spacer(minLength: 8)

                Text("\(RoutePlannerModel.minutes(trip.durationSec)) · \(boardingLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(trip.legs) { leg in
                    legRow(leg)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dataCard(cornerRadius: Theme.Radius.xxl)
    }

    private func legRow(_ leg: RoutePlanLeg) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // The route number goes on its own coloured tile, as everywhere
            // else in the app — inline it would run straight into the
            // departure time ("16:31 35") and read as one number.
            if leg.isWalk {
                Image(systemName: "figure.walk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: 30, height: 24)
                    .background(
                        Theme.muted,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    )
            } else {
                RouteTile(
                    short: leg.routeShortName ?? "?",
                    colorHex: leg.routeColor,
                    textHex: nil,
                    size: .small
                )
            }

            if leg.isWalk {
                Text("Gyalog \(RoutePlannerModel.minutes(leg.durationSec)) — \(leg.toName)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(boardingLine(leg))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(alightingLine(leg))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    if let note = punctualityNote(leg) {
                        Text(note.text)
                            .font(.system(size: 11))
                            .foregroundStyle(note.tone)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Copy

    private func boardingLine(_ leg: RoutePlanLeg) -> String {
        let time = RoutePlannerModel.hourMinute(leg.start)
        let mode = Self.modeLabel[leg.mode.uppercased()] ?? "járat"
        return "\(time) — \(leg.fromName), \(mode)ra fel"
    }

    private func alightingLine(_ leg: RoutePlanLeg) -> String {
        var text = "érkezés \(RoutePlannerModel.hourMinute(leg.end)) — \(leg.toName)"
        if !leg.intermediateStopNames.isEmpty {
            text += " (\(leg.intermediateStopNames.count) megálló)"
        }
        return text
    }

    private static let modeLabel: [String: String] = [
        "BUS": "busz",
        "TRAM": "villamos",
        "TROLLEYBUS": "trolibusz",
        "TROLLEY": "trolibusz",
        "RAIL": "vonat",
    ]

    /// Under 30 s of average deviation is not worth calling late or early.
    private func punctualityNote(_ leg: RoutePlanLeg) -> (text: String, tone: Color)? {
        guard let info = model.delayInfo(for: leg), let avg = info.avgDelaySec else { return nil }

        let minutes = Int((abs(avg) / 60).rounded())
        let magnitude = minutes > 0 ? "\(minutes) perccel" : "\(Int(abs(avg))) mp-cel"

        let text: String
        if abs(avg) < 30 {
            text = "átlagosan pontos"
        } else if avg > 0 {
            text = "átlagosan \(magnitude) késik"
        } else {
            text = "átlagosan \(magnitude) korábban jön"
        }

        let tone: Color = avg > 60 ? Theme.late : (avg < -60 ? Theme.early : Theme.mutedForeground)
        return ("\(text) (\(info.samples) mérésből)", tone)
    }

    private var boardingLabel: String {
        let count = trip.legs.filter { !$0.isWalk }.count
        return count > 0 ? "\(count) járattal" : "gyalog"
    }
}

/// The answer for a moment already past: what the journey actually took,
/// measured, versus what the timetable claimed.
struct HistoricEstimateCard: View {
    let estimate: SegmentEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let short = estimate.routeShort {
                    RouteTile(short: short, colorHex: estimate.routeColor, textHex: nil, size: .small)
                }
                if let headsign = estimate.headsign {
                    Text(headsign)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("~\(RoutePlannerModel.duration(estimate.p50S))")
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
            }

            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            if estimate.legs.count > 1 {
                Divider().overlay(Theme.border)
                VStack(spacing: 6) {
                    ForEach(Array(estimate.legs.enumerated()), id: \.offset) { _, leg in
                        HStack(spacing: 8) {
                            Text("\(leg.from) → \(leg.to)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.mutedForeground)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(RoutePlannerModel.duration(leg.p50S))
                                .font(Theme.mono(11, weight: .regular))
                                .foregroundStyle(Theme.foreground)
                        }
                    }
                }
            }

            Text(provenance)
                .font(.system(size: 11))
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dataCard(cornerRadius: Theme.Radius.xxl)
    }

    /// Anything under half a minute over schedule is noise, not a delay.
    private var summary: String {
        let excess = max(0, estimate.p50S - estimate.schedS)
        let measured = RoutePlannerModel.duration(estimate.p50S)
        guard excess > 30 else {
            return "Várható menetidő a mért adatok alapján \(measured) — nagyjából a menetrend szerint."
        }
        return "Várható menetidő a mért adatok alapján \(measured) — menetrend szerint \(RoutePlannerModel.duration(estimate.schedS)), tehát átlagosan \(RoutePlannerModel.duration(excess))-cel több kellett."
    }

    private var provenance: String {
        guard estimate.samples > 0 else {
            return "Nincs mért adat ehhez az időszakhoz, a menetrendi időt mutatjuk."
        }
        let exactness = estimate.scheduleExact ? "" : " (nem az adott napra érvényes menetrend alapján)"
        return "\(estimate.samples) mérésből, \(estimate.confidence) megbízhatóságú becslés\(exactness)."
    }
}
