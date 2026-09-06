//
//  ApproachStripView.swift
//  MVK++ Phone App
//

import CoreLocation
import SwiftUI

/// The band that relates one specific vehicle to where the rider is standing:
/// nearest stop, how far the bus still has to travel *along its route*, and
/// how far off schedule it is running.
struct ApproachStripView: View {
    let tripId: String?
    let shape: [CLLocationCoordinate2D]?
    let vehicle: ApproachEngine.VehicleFix?
    let stops: [Stop]
    var deviationSec: Int?
    /// Drop the strip's own background when it sits inside a glass card that
    /// already provides one.
    var isTransparent = false

    @EnvironmentObject private var location: LocationProvider
    @StateObject private var engine = ApproachEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HereChip(stops: stops, onGlass: isTransparent)

            if let note = stateNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(isTransparent ? .white.opacity(0.75) : Theme.mutedForeground)
            }

            if let inbound = inboundLine {
                Text(inbound)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isTransparent ? .white : Theme.primary)
            }

            if DelayFormat.state(deviationSec) != .unknown {
                Text(DelayFormat.sentence(deviationSec))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DelayFormat.tone(deviationSec))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, isTransparent ? 0 : 10)
        .background(isTransparent ? Color.clear : Theme.muted.opacity(0.25))
        .task(id: taskKey) { recompute() }
        .onChange(of: location.position) { _, _ in recompute() }
        .accessibilityLabel("A jármű és a helyzetem")
    }

    private func recompute() {
        engine.update(tripId: tripId, shape: shape, vehicle: vehicle, position: location.position)
    }

    /// Recomputes whenever the vehicle moves or the followed trip changes.
    private var taskKey: String {
        "\(tripId ?? "-")|\(vehicle?.lat ?? 0)|\(vehicle?.lon ?? 0)"
    }

    private var stateNote: String? {
        switch engine.approach.state {
        case .noGPS: return "Nincs helymeghatározás."
        case .offRoute: return "A járat nem halad el melletted."
        case .passed: return "A jármű már elhaladt."
        // `noVehicle` is not reported: the card above already shows the
        // vehicle's plate and speed, so claiming none has checked in only ever
        // contradicted what the rider can see.
        case .noVehicle, .inbound: return nil
        }
    }

    private var inboundLine: String? {
        guard engine.approach.state == .inbound,
              let distanceKm = engine.approach.distanceKm
        else { return nil }

        let distance = Geo.formatDistance(distanceKm)
        guard let etaMin = engine.approach.etaMin else { return "\(distance) múlva ér ide" }
        if etaMin <= 0 { return "Bármelyik pillanatban ideér · \(distance)" }
        return "\(etaMin) perc múlva ér ide · \(distance)"
    }
}
