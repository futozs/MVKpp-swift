//
//  VehicleFocusCard.swift
//  MVK++ Phone App
//

import SwiftUI

/// The panel shown while the map is following one vehicle: which run it is,
/// which bus, how fast, and how far it still has to come to reach the rider.
///
/// It floats over the map as Liquid Glass rather than sitting flush against
/// the bottom edge — the map keeps running underneath, and the card reads as
/// what it is: a control hovering above the content, not a second screen.
struct VehicleFocusCard: View {
    let tripId: String
    let vehicleId: String?
    let stops: [Stop]
    @ObservedObject var model: TripPathModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider().overlay(.white.opacity(0.15))

            ApproachStripView(
                tripId: model.path?.trip ?? tripId,
                shape: model.shape,
                vehicle: model.vehicleFix,
                stops: stops,
                deviationSec: model.path?.scheduleDeviationSec,
                isTransparent: true
            )
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingGlass(cornerRadius: Theme.Radius.xxl)
        .accessibilityLabel("Követett jármű")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RouteTile(
                short: model.path?.route ?? "…",
                colorHex: model.path?.color,
                textHex: model.path?.text,
                size: .large
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(model.path?.headsign ?? "Menet betöltése…")
                        .font(.system(size: 14, weight: .bold))
                        // White throughout: this card sits on glass over live
                        // map tiles, where the muted palette disappears.
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if model.path?.vehicle != nil { LiveDot(size: 7) }
                }

                FlowLayout(spacing: 10, lineSpacing: 4) {
                    if let shownId {
                        Text(shownId)
                            .font(Theme.mono(14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                .white.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                    }

                    if let speedKmh {
                        HStack(spacing: 4) {
                            Image(systemName: "gauge.with.dots.needle.33percent")
                                .font(.system(size: 11))
                            Text("\(speedKmh) km/h").font(Theme.mono(12, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(isMoving ? 1 : 0.65))
                    }

                    if model.isLost {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text("A jármű kiesett a jelentésből")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    // A generous target: this is the only way out of follow
                    // mode, and the tab bar is hidden while it is on.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Menetkövetés vége")
        }
        .padding(.horizontal, 14)
    }

    /// Falls back to the registration the rider tapped through with, so the
    /// card is not blank while the first path response is in flight.
    private var shownId: String? { model.path?.vehicle?.id ?? vehicleId }

    private var speedKmh: Int? {
        guard let speed = model.path?.vehicle?.speed else { return nil }
        return Int((speed * 3.6).rounded())
    }

    private var isMoving: Bool { (speedKmh ?? 0) > 2 }
}
