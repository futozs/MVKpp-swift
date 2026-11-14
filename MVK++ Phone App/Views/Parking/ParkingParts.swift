//
//  ParkingParts.swift
//  MVK++ Phone App
//

import SwiftUI

/// Route short name → route, for the chip colours. A train's label is
/// "IC 191": its colour comes from the category ("IC").
typealias ParkingRouteLookup = (String?) -> Route?

enum ParkingStyle {
    static let chipFallback = "3A4A44"

    static func hex(_ value: String?, _ fallback: String) -> Color {
        guard let value, value.count == 6, UInt64(value, radix: 16) != nil else { return Theme.hex(fallback) }
        return Theme.hex(value)
    }
}

/// The route's coloured tile, the same shape as on the map.
struct ParkingRouteChip: View {
    let route: String?
    let lookup: ParkingRouteLookup
    var height: CGFloat = 18
    var minWidth: CGFloat = 26
    var fontSize: CGFloat = 11

    var body: some View {
        if let route {
            let r = lookup(route)
            Text(route)
                .font(Theme.mono(fontSize, weight: .bold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .frame(minWidth: minWidth, minHeight: height, maxHeight: height)
                .foregroundStyle(ParkingStyle.hex(r?.text, "FFFFFF"))
                .background(ParkingStyle.hex(r?.color, ParkingStyle.chipFallback), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}

/// Live signal: a green dot with a ping ring (Tailwind `animate-ping`);
/// silent: an empty ring.
struct ParkingSignalDot: View {
    let online: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ping {
        var scale: CGFloat = 1
        var opacity: Double = 1
    }

    var body: some View {
        if online {
            Circle()
                .fill(Theme.live)
                .frame(width: 8, height: 8)
                .background {
                    if !reduceMotion {
                        KeyframeAnimator(initialValue: Ping(), repeating: true) { ping in
                            Circle()
                                .fill(Theme.live.opacity(0.6))
                                .scaleEffect(ping.scale)
                                .opacity(ping.opacity)
                        } keyframes: { _ in
                            let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1))
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(2, duration: 0.75, timingCurve: curve)
                                LinearKeyframe(2, duration: 0.25)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(0, duration: 0.75, timingCurve: curve)
                                LinearKeyframe(0, duration: 0.25)
                            }
                        }
                    }
                }
                .accessibilityLabel("Élő GPS-jel")
        } else {
            Circle()
                .strokeBorder(Theme.mutedForeground.opacity(0.6), lineWidth: 1)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Nincs élő jel")
        }
    }
}

/// The next departure. Dashed border = forecast (as in the Megállófigyelő),
/// solid = MVK has already assigned the trip.
struct ParkingTipChip: View {
    enum Variant { case full, tile, stall }

    let tip: ParkingTripTip
    let lookup: ParkingRouteLookup
    let midnight: Double
    let now: Double
    var variant: Variant = .full

    var body: some View {
        let until = ParkingFormat.until(tip, midnight: midnight, now: now)
        let extra: String? = {
            switch variant {
            case .stall: return nil
            case _ where !tip.certain: return ParkingFormat.pct(tip.confidence)
            case .full: return ParkingFormat.untilText(until)
            case .tile: return until < 60 ? "most" : ParkingFormat.duration(until)
            }
        }()
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        HStack(spacing: variant == .full ? 6 : 4) {
            if variant == .full {
                Text("→").foregroundStyle(Theme.mutedForeground)
            }
            ParkingRouteChip(route: tip.route, lookup: lookup, height: 16, minWidth: 22, fontSize: 10)
            Text(ParkingFormat.hm(daySec: tip.startS))
                .font(Theme.mono(11, weight: .semibold))
            if let extra {
                Spacer(minLength: 2)
                Text(extra)
                    .lineLimit(1)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.foreground.opacity(tip.certain ? 1 : 0.9))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(tip.certain ? Theme.primary.opacity(0.10) : .clear, in: shape)
        .overlay(
            shape.strokeBorder(
                Theme.primary.opacity(tip.certain ? 0.5 : 0.45),
                style: StrokeStyle(lineWidth: 1, dash: tip.certain ? [] : [3, 2])
            )
        )
        .accessibilityLabel(tip.certain
            ? "\(TransitModes.isRegionalId(tip.tripId) ? "A MÁV" : "Az MVK") már kiadta neki: \(tip.route) \(ParkingFormat.hm(daySec: tip.startS))"
            : "Előrejelzés a korábbi fordák alapján, \(ParkingFormat.pct(tip.confidence)) bizonyossággal")
    }
}

/// Favourite parking toggle (favourites come first, and sync to the cloud).
struct ParkingFavoriteButton: View {
    let active: Bool
    let name: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: active ? "star.fill" : "star")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? Theme.primary : Theme.mutedForeground.opacity(0.6))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active ? "\(name): levétel a kedvencekről" : "\(name): kedvenc parkoló")
    }
}

/// The last 14 days: out (filled) or resting (empty), yesterday on the right.
struct ParkingPresenceStrip: View {
    let recent: String
    var tall = false

    var body: some View {
        let out = recent.filter { $0 == "1" }.count
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(c == "1" ? Theme.primary.opacity(0.8) : Theme.mutedForeground.opacity(0.2))
                    .frame(width: 5, height: tall ? 16 : 10)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Az utolsó \(recent.count) napból \(out) napon volt kint")
    }
}

/// The web's segmented control: a muted well, the chosen segment filled
/// with the primary green.
struct ParkingSegmented<ID: Hashable>: View {
    let options: [(id: ID, label: String)]
    @Binding var selection: ID
    var fill = false
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(options, id: \.id) { option in
                let on = option.id == selection
                Button {
                    withAnimation(Theme.Motion.fastAnimation) { selection = option.id }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, compact ? 8 : 10)
                        .padding(.vertical, compact ? 4 : 6)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                        .background(on ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(compact ? 2 : 4)
        .background(Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// A section heading: uppercase, wide tracking, the count in the foreground.
struct ParkingSectionTitle: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .tracking(1)
                .foregroundStyle(Theme.mutedForeground)
            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(Theme.foreground)
        }
        .font(.system(size: 13, weight: .bold))
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The dashed empty-state box.
struct ParkingEmptyBox: View {
    let text: String
    var verticalPadding: CGFloat = 32

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Theme.mutedForeground)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
    }
}

extension View {
    /// The web's `rounded-2xl border bg-card shadow-sm` card.
    func parkingCard(border: Color = Theme.border, radius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(Theme.card, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .mvkShadow(Theme.Shadow.sm)
    }
}

/// CSS `grid-template-columns: repeat(auto-fill, minmax(min, 1fr))`: as many
/// equal columns as fit, every cell in a row stretched to the row's height.
struct ParkingAdaptiveGrid: Layout {
    var minWidth: CGFloat
    var spacing: CGFloat = 0

    private func columns(_ width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (minWidth + spacing)))
    }

    private func rowHeights(_ subviews: Subviews, columnWidth: CGFloat, count: Int) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: count).map { start in
            subviews[start..<min(start + count, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minWidth
        let count = columns(width)
        let columnWidth = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let heights = rowHeights(subviews, columnWidth: columnWidth, count: count)
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = columns(bounds.width)
        let columnWidth = (bounds.width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let heights = rowHeights(subviews, columnWidth: columnWidth, count: count)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<count {
                let index = row * count + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (columnWidth + spacing), y: y),
                    proposal: ProposedViewSize(width: columnWidth, height: height)
                )
            }
            y += height + spacing
        }
    }
}
