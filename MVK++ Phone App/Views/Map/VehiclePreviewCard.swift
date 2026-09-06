//
//  VehiclePreviewCard.swift
//  MVK++ Phone App
//

import SwiftUI

/// What a tapped vehicle shows without leaving the map: which run, which bus,
/// how fast — and the one action worth offering.
///
/// Deliberately a card over the map rather than a sheet: the rider tapped a
/// dot *on the map*, and a sheet would cover the very thing they were looking
/// at while the map zooms to it. Same Liquid Glass material as the follow
/// card, so the two read as one family — and all text is white, because the
/// muted palette is illegible against glass over live tiles.
struct VehiclePreviewCard: View {
    let annotation: VehicleAnnotation
    var onFollow: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RouteTile(
                    short: annotation.routeShort,
                    colorHex: annotation.routeColor,
                    textHex: annotation.routeText,
                    size: .large
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(annotation.headsign.isEmpty ? "Járat" : annotation.headsign)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Text(annotation.vehicleId)
                            .font(Theme.mono(15))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                .white.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )

                        if let speedText {
                            HStack(spacing: 4) {
                                Image(systemName: "gauge.with.dots.needle.33percent")
                                    .font(.system(size: 11))
                                Text(speedText).font(Theme.mono(12, weight: .semibold))
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bezárás")
            }

            if !annotation.tripId.isEmpty {
                Button(action: onFollow) {
                    Label("Követés a térképen", systemImage: "scope")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingGlass(cornerRadius: Theme.Radius.xxl)
    }

    private var speedText: String? {
        guard let speed = annotation.speed else { return nil }
        return "\(Int((speed * 3.6).rounded())) km/h"
    }
}
