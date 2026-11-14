//
//  MapControls.swift
//  MVK++ Phone App
//
//  The map's one control element (`controls/MapControl.tsx`): the same 44 pt
//  size in every corner, the same glass, the same pressed / active state.
//

import SwiftUI

struct MapControlButton: View {
    let systemImage: String
    let label: String
    var showLabel = false
    var active = false
    var badge: Int?
    var busy = false
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.pulse, isActive: busy)
                if showLabel {
                    Text(label)
                        .font(Theme.sans(13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(active ? Theme.primary : Theme.foreground)
            .padding(.horizontal, showLabel ? 14 : 0)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        }
        .buttonStyle(MapControlPressStyle())
        .glassEffect(
            .regular.tint(active ? Theme.primary.opacity(0.18) : Theme.card.opacity(0.35)).interactive(),
            in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(Theme.primaryForeground)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Theme.primary, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.background, lineWidth: 2))
                    .offset(x: 6, y: -6)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct MapControlPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}

/// A floating notice in a corner (geolocation error, 3D failure).
struct MapNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.sans(11.5))
            .foregroundStyle(Theme.mutedForeground)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 220, alignment: .leading)
            .glassEffect(.regular.tint(Theme.card.opacity(0.5)), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Map cover

/// The top edge (global y) of a panel covering the full width of the map's
/// bottom (the followed vehicle's card, the ride panel) — the web's
/// `data-map-cover`. The map keeps the followed bus centred in the part still
/// visible above it. `.infinity` when nothing covers it.
struct MapCoverKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

extension View {
    /// Marks a bottom-anchored, full-width panel as covering the map.
    func mapCover() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: MapCoverKey.self, value: proxy.frame(in: .global).minY)
            }
        )
    }
}
