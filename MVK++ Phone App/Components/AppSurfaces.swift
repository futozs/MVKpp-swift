//
//  AppSurfaces.swift
//  MVK++ Phone App
//

import SwiftUI

// `AppBackground` and `mvkBackground()` live in Shared/Theme/GlassCard.swift —
// the Watch target uses them too, so they are declared once for all targets.

extension View {

    /// The content layer: departures, timetables, arrival rows.
    ///
    /// Deliberately *not* glass. Liquid Glass is for the controls that float
    /// over content; dense numeric data needs a stable, opaque ground or the
    /// digits fight whatever is drifting underneath them.
    func dataCard(cornerRadius: CGFloat = Theme.Radius.xl, padding: CGFloat? = nil) -> some View {
        modifier(DataCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    /// The control layer: buttons, chips, panels that hover above the map.
    func floatingGlass(
        tint: Color? = nil,
        interactive: Bool = false,
        cornerRadius: CGFloat = Theme.Radius.lg
    ) -> some View {
        modifier(FloatingGlassModifier(tint: tint, interactive: interactive, cornerRadius: cornerRadius))
    }

    /// A circular glass control — the locate button, the stop-code jump.
    func glassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(GlassCircleModifier(tint: tint, interactive: interactive))
    }
}

private struct DataCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .padding(padding ?? 0)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
            .mvkShadow(Theme.Shadow.lg)
    }
}

private struct FloatingGlassModifier: ViewModifier {
    let tint: Color?
    let interactive: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content.glassEffect(glass, in: shape)
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

private struct GlassCircleModifier: ViewModifier {
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: 44, height: 44)
            .glassEffect(glass, in: Circle())
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// A section heading in the web app's voice: small, uppercase, wide-tracked.
struct SectionLabel: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.mutedForeground)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(Theme.mono(11, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
    }
}

/// Inline error, matching the web app's destructive-tinted notice.
struct ErrorNotice: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Theme.destructive)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Theme.destructive.opacity(0.10),
                in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.destructive.opacity(0.30), lineWidth: 1)
            )
    }
}

/// A round glass button whose tap target is the whole circle.
///
/// Applying `.glassCircle()` to a `Button` sizes the *glass* to 44 pt but
/// leaves the button's hit area at whatever the label draws — for a single SF
/// Symbol that is about 20 pt in the middle of a 44 pt disc, so four taps out
/// of five land on nothing and the control reads as broken. Sizing inside the
/// label, with an explicit `contentShape`, is what makes the visible circle
/// and the tappable circle the same circle.
struct GlassCircleButton<Label: View>: View {
    var tint: Color?
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    /// Apple's minimum comfortable target, and the size the glass already
    /// draws.
    private static var diameter: CGFloat { 44 }

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: Self.diameter, height: Self.diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle(tint: tint)
    }
}
