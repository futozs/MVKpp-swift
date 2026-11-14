//
//  DepartureRow.swift
//  MVK++ Watch App
//

import SwiftUI

/// One departure in a single line: tile, headsign, countdown — with the
/// delay and the vehicle beneath the headsign. Used wherever a stop shows
/// more than its next bus.
struct DepartureRow: View {
    let arrival: ArrivalItem
    var showsVehicle = true

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            RouteTile(short: arrival.route, colorHex: arrival.color, textHex: arrival.text, size: .medium)
                .opacity(arrival.isCancelled ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(arrival.headsign)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .strikethrough(arrival.isCancelled)
                HStack(spacing: 4) {
                    if arrival.isCancelled {
                        Text("Kimarad")
                            .foregroundStyle(Theme.destructive)
                    } else {
                        DelayText(arrival: arrival, short: true)
                        if showsVehicle, let vehicle = vehicleLabel {
                            Text(vehicle)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
            }

            Spacer(minLength: 2)

            CountdownView(etaMin: arrival.etaMin)
                .opacity(arrival.isCancelled ? 0.4 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// The live vehicle, or the predicted one marked with "~" like the web.
    private var vehicleLabel: String? {
        if let id = arrival.vehicle?.id { return "#\(TransitModes.displayVehicleId(id))" }
        if let predicted = arrival.predictedVehicle?.id { return "~\(TransitModes.displayVehicleId(predicted))" }
        return nil
    }
}

/// The delay, or "menetrend" for a run with no live match — a dash would
/// read as "on time".
struct DelayText: View {
    let arrival: ArrivalItem
    /// "+3 p" instead of "+3 perc", for a line shared with the vehicle.
    var short = false

    var body: some View {
        if arrival.delaySec == nil, !arrival.live {
            Text("menetrend")
                .foregroundStyle(Theme.mutedForeground.opacity(0.8))
        } else {
            Text(label)
                .foregroundStyle(DelayFormat.tone(arrival.delaySec))
        }
    }

    private var label: String {
        let full = DelayFormat.label(arrival.delaySec)
        guard short else { return full }
        return DelayFormat.state(arrival.delaySec) == .ontime ? "pontos" : full.replacingOccurrences(of: " perc", with: " p")
    }
}

/// The rider-facing stop number ("SP84" → "84"); a regional stop keeps no
/// number worth showing.
enum StopCode {
    static func short(_ stopId: String) -> String? {
        guard !TransitModes.isRegionalId(stopId) else { return nil }
        let digits = stopId.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }
}

/// The green-edged stop number plate, as on the web's stop cards.
struct StopCodePlate: View {
    let code: String

    var body: some View {
        Text(code)
            .font(Theme.mono(10, weight: .heavy))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.primary.opacity(0.6), lineWidth: 1)
            )
    }
}

/// Where the next bus is right now, when the feed knows.
struct ApproachLine: View {
    let arrival: ArrivalItem

    var body: some View {
        if let text {
            HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(180))
                Text(text)
                    .lineLimit(2)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.live)
        }
    }

    private var text: String? {
        if let desc = arrival.progressDesc, !desc.isEmpty { return desc }
        guard let current = arrival.currentStopName, !current.isEmpty else { return nil }
        if let km = arrival.distanceToStopKm { return "\(current) · \(Geo.formatDistance(km))" }
        return current
    }
}
