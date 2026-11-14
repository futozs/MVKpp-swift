//
//  HereChip.swift
//  MVK++ Phone App
//

import SwiftUI

/// Anchors the rider in the network: which stop they are standing at (or
/// nearest to) and how far it is. Before a fix exists it is the button that
/// asks for one.
struct HereChip: View {
    let stops: [Stop]
    /// On a glass card over the map the muted palette disappears; everything
    /// switches to white.
    var onGlass = false

    @EnvironmentObject private var location: LocationProvider

    var body: some View {
        if let position = location.position {
            resolved(position)
        } else if location.status == .denied || location.status == .unavailable {
            Text(location.errorMessage ?? "A helymeghatározás nem érhető el.")
                .font(Theme.sans(11))
                .foregroundStyle(secondary)
        } else {
            askButton
        }
    }

    private var askButton: some View {
        Button {
            location.start()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10))
                    .symbolEffect(.pulse, isActive: location.status == .requesting)
                Text(location.status == .requesting ? "Helyzet keresése…" : "Hol vagyok?")
                    .font(Theme.sans(11, weight: .semibold))
            }
            .foregroundStyle(Theme.early)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(Theme.early.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.early.opacity(0.40), lineWidth: 1))
        .disabled(location.status == .requesting)
    }

    private var primary: Color { onGlass ? .white : Theme.foreground }
    private var secondary: Color { onGlass ? .white.opacity(0.75) : Theme.mutedForeground }

    private func resolved(_ position: GeoPosition) -> some View {
        let hit = Geo.nearest(stops, lat: position.lat, lon: position.lon)

        return HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.early)
                .opacity(location.isStale ? 0.5 : 1)

            Text("Itt vagy")
                .font(Theme.sans(11, weight: .semibold))
                .foregroundStyle(secondary)

            if let hit {
                Text(hit.item.name)
                    .font(Theme.sans(11, weight: .medium))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                Text(Geo.formatDistance(hit.km))
                    .font(Theme.mono(11, weight: .regular))
                    .foregroundStyle(secondary)
                    .layoutPriority(1)
            } else {
                Text("a megállólistán kívül")
                    .font(Theme.sans(11))
                    .foregroundStyle(secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
