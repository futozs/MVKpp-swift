//
//  ApproachStripView.swift
//  MVK++ Phone App
//

import CoreLocation
import SwiftUI

/// The band relating one vehicle to where the rider is — the web app's
/// `transit/ApproachStrip`: nearest stop, whether the run passes by at all,
/// and how far off schedule it is. Without a location there is nothing to say
/// about the rider, so only the schedule deviation remains (or nothing).
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
        Group {
            if located || hasDelay {
                VStack(alignment: .leading, spacing: 6) {
                    if located { HereChip(stops: stops, onGlass: isTransparent) }

                    if let note = stateNote {
                        Text(note)
                            .font(Theme.sans(11))
                            .foregroundStyle(isTransparent ? .white.opacity(0.75) : Theme.mutedForeground)
                    }

                    if hasDelay {
                        Text(DelayFormat.sentence(deviationSec))
                            .font(Theme.sans(11, weight: .semibold))
                            .foregroundStyle(DelayFormat.tone(deviationSec))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, isTransparent ? 0 : 16)
                .padding(.vertical, isTransparent ? 0 : 10)
                .background(isTransparent ? Color.clear : Theme.muted.opacity(0.25))
                .overlay(alignment: .top) {
                    if !isTransparent { Rectangle().fill(Theme.border).frame(height: 1) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("A busz és a helyzetem")
            }
        }
        .task(id: taskKey) { recompute() }
        .onChange(of: location.position) { _, _ in recompute() }
    }

    private var located: Bool { location.position != nil }
    private var hasDelay: Bool { DelayFormat.state(deviationSec) != .unknown }

    private func recompute() {
        engine.update(tripId: tripId, shape: shape, vehicle: vehicle, position: location.position)
    }

    private var taskKey: String {
        "\(tripId ?? "-")|\(vehicle?.lat ?? 0)|\(vehicle?.lon ?? 0)"
    }

    private var stateNote: String? {
        guard located else { return nil }
        switch engine.approach.state {
        case .noVehicle: return "Erre a menetre még nem jelentkezett be jármű."
        case .offRoute: return "A járat nem halad el melletted."
        case .noGPS, .inbound, .passed: return nil
        }
    }
}
