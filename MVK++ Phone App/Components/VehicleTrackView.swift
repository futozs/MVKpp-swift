//
//  VehicleTrackView.swift
//  MVK++ Phone App
//

import SwiftUI

/// The vehicle serving this departure — the web app's `transit/VehicleTrack`
/// at phone width: which bus, how fast, where it is, and (the whole band is
/// the button) following it on the map.
struct VehicleTrackView: View {
    let vehicle: ArrivalVehicle?
    /// The vehicle's caption (a train's number); a Volán coach's plate by default.
    var label: String?
    var progressDesc: String?
    var onTrack: (() -> Void)?

    init(vehicle: ArrivalVehicle?, label: String? = nil, progressDesc: String? = nil, onTrack: (() -> Void)? = nil) {
        self.vehicle = vehicle
        self.label = label
        self.progressDesc = progressDesc
        self.onTrack = onTrack
    }

    var body: some View {
        if vehicle != nil || progressDesc != nil {
            if let onTrack, vehicle != nil {
                Button(action: onTrack) { band(trackable: true) }
                    .buttonStyle(PressableBandStyle())
                    .accessibilityLabel("\(vehicleText) követése a térképen")
            } else {
                band(trackable: false)
            }
        }
    }

    private var vehicleText: String {
        label ?? vehicle.map { TransitIds.displayVehicleId($0.id, plate: $0.plate) } ?? ""
    }

    private func band(trackable: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        return HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.primary)

            if vehicle != nil {
                Text(vehicleText)
                    .font(Theme.mono(16))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text("nincs jármű")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
            }

            if let speedKmh {
                Text("\(speedKmh) km/h")
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(speedKmh > 2 ? Theme.foreground : Theme.mutedForeground)
                    .fixedSize()
            }

            if let progressDesc {
                Text(progressDesc)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if trackable {
                Image(systemName: "location.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(6)
                    .background(Theme.primary.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.primary.opacity(0.07), in: shape)
        .overlay(shape.strokeBorder(Theme.primary.opacity(0.25), lineWidth: 1))
        .mvkShadow(Theme.Shadow.xs)
        .contentShape(shape)
    }

    private var speedKmh: Int? {
        guard let speed = vehicle?.speed else { return nil }
        return Int((speed * 3.6).rounded())
    }
}

/// The web's `active:scale-[0.99]` plus the hover tint, for a tappable band.
struct PressableBandStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}
