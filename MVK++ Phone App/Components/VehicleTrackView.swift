//
//  VehicleTrackView.swift
//  MVK++ Phone App
//

import SwiftUI

/// The vehicle actually serving this departure: which bus, how fast, where it
/// is on its run, and a way to follow it on the map.
///
/// The registration number is prominent on purpose — it is what a rider reads
/// off the front of the bus to confirm this is the one they were waiting for.
struct VehicleTrackView: View {
    let vehicle: ArrivalVehicle?
    var progressDesc: String?
    var onTrack: (() -> Void)?

    var body: some View {
        if vehicle == nil && progressDesc == nil {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("JÁRMŰ")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.mutedForeground)

                    if let vehicle {
                        Text(vehicle.id)
                            .font(Theme.mono(20))
                            .foregroundStyle(Theme.foreground)
                    } else {
                        Text("Nincs hozzárendelve")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }

                Spacer(minLength: 8)

                if let speedKmh {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SEBESSÉG")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.mutedForeground)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(speedKmh)")
                                .font(Theme.mono(20))
                                .foregroundStyle(isMoving ? Theme.foreground : Theme.mutedForeground)
                            Text("km/h")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                }
            }

            if let progressDesc {
                Divider().overlay(Theme.primary.opacity(0.15))
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.primary)
                        .padding(.top, 2)
                    Text(progressDesc)
                        .font(.subheadline)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let onTrack, vehicle != nil {
                Button(action: onTrack) {
                    Text("Követés a térképen")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                .tint(Theme.primary)
            }
        }
        .padding(12)
        .background(
            Theme.primary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.primary.opacity(0.25), lineWidth: 1)
        )
    }

    private var speedKmh: Int? {
        guard let speed = vehicle?.speed else { return nil }
        return Int((speed * 3.6).rounded())
    }

    /// Below 2 km/h the vehicle is stopped, not crawling — shown muted so the
    /// number does not read as progress.
    private var isMoving: Bool { (speedKmh ?? 0) > 2 }
}
