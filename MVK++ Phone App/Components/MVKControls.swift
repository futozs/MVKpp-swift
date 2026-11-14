//
//  MVKControls.swift
//  MVK++ Phone App
//

import SwiftUI

/// The web's shadcn `Button` (`components/ui/button.tsx`): its cva variants
/// and sizes, medium-weight label, 16 px icons, and a hit area of at least
/// 44 pt around the drawn button.
struct MVKButtonStyle: ButtonStyle {
    enum Variant { case primary, destructive, outline, secondary, ghost, link }
    enum Size { case regular, small, large, icon }

    var variant: Variant = .primary
    var size: Size = .regular
    var fullWidth = false
    /// A `className` override of the variant's fill (`bg-card`).
    var fill: Color?
    /// A `className` override of the outline colour (`border-primary/50`).
    var border: Color?
    /// A `className` override of the size's height (`h-11`).
    var height: CGFloat?

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        let pressed = configuration.isPressed
        return configuration.label
            .font(Theme.sans(size == .small ? 12 : 14, weight: .medium))
            .labelStyle(MVKButtonLabelStyle())
            .lineLimit(1)
            .foregroundStyle(foreground(pressed: pressed))
            .underline(variant == .link && pressed)
            .padding(.horizontal, horizontalPadding)
            .frame(width: size == .icon ? resolvedHeight : nil, height: resolvedHeight)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background(pressed: pressed), in: shape)
            .overlay {
                if let stroke = border ?? (variant == .outline ? Theme.input : nil) {
                    shape.strokeBorder(stroke, lineWidth: 1)
                }
            }
            .mvkShadow(hasShadow ? Theme.Shadow.sm : Theme.Shadow.none)
            .contentShape(.interaction, shape.inset(by: -max(0, (44 - resolvedHeight) / 2)))
            .opacity(isEnabled ? 1 : 0.5)
            .animation(Theme.Motion.fastAnimation, value: pressed)
    }

    private var resolvedHeight: CGFloat {
        if let height { return height }
        return switch size {
        case .small: 32
        case .large: 40
        case .regular, .icon: 36
        }
    }

    private var horizontalPadding: CGFloat {
        if variant == .link { return 0 }
        switch size {
        case .small: return 12
        case .large: return 32
        case .regular: return 16
        case .icon: return 0
        }
    }

    private var hasShadow: Bool {
        switch variant {
        case .primary, .destructive, .outline, .secondary: true
        case .ghost, .link: false
        }
    }

    private func foreground(pressed: Bool) -> Color {
        switch variant {
        case .primary: Theme.primaryForeground
        case .destructive: Theme.destructiveForeground
        case .secondary: Theme.secondaryForeground
        case .outline, .ghost: pressed ? Theme.accentForeground : Theme.foreground
        case .link: Theme.primary
        }
    }

    private func background(pressed: Bool) -> Color {
        if let fill, !pressed { return fill }
        return switch variant {
        case .primary: Theme.primary.opacity(pressed ? 0.9 : 1)
        case .destructive: Theme.destructive.opacity(pressed ? 0.9 : 1)
        case .secondary: Theme.secondary.opacity(pressed ? 0.8 : 1)
        case .outline: pressed ? Theme.accent : Theme.background
        case .ghost: pressed ? Theme.accent : Color.clear
        case .link: Color.clear
        }
    }
}

/// `gap-2` between icon and title; lucide's 16 px icons match SF Symbols at
/// about 14 pt.
private struct MVKButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 14, weight: .medium))
            configuration.title
        }
    }
}

extension ButtonStyle where Self == MVKButtonStyle {
    static func mvk(
        _ variant: MVKButtonStyle.Variant = .primary,
        size: MVKButtonStyle.Size = .regular,
        fullWidth: Bool = false,
        fill: Color? = nil,
        border: Color? = nil,
        height: CGFloat? = nil
    ) -> MVKButtonStyle {
        MVKButtonStyle(variant: variant, size: size, fullWidth: fullWidth, fill: fill, border: border, height: height)
    }
}

/// The web dialog's header (`DialogHeader` with `px-5 py-4 border-b`): icon,
/// title, description.
struct SheetHeader: View {
    let icon: String?
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.primary)
                }
                Text(title)
                    .font(Theme.sans(18, weight: .semibold))
                    .tracking(-0.45)
                    .foregroundStyle(Theme.foreground)
            }
            if let subtitle {
                Text(subtitle)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// `DialogContent`'s close control with a 44 pt hit area.
struct DialogCloseButton: View {
    enum Style {
        /// The shadcn default: a 16 px cross at 70% opacity, 16 pt in.
        case standard
        /// The news dialog's own: an 18 px muted cross in a 36 pt box, 10 pt in.
        case large
    }

    var style: Style = .standard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: style == .large ? 15 : 13, weight: .medium))
                .foregroundStyle(style == .large ? Theme.mutedForeground : Theme.foreground.opacity(0.7))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding([.top, .trailing], style == .large ? 6 : 2)
        .accessibilityLabel("Bezárás")
    }
}

/// The web's small uppercase section label (`text-[11px] font-semibold uppercase tracking-wide`).
struct CapsLabel: View {
    let text: String
    var color: Color = Theme.mutedForeground

    init(_ text: String, color: Color = Theme.mutedForeground) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.sans(11, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(color)
    }
}

/// The web's `Switch`: a small primary-tinted toggle with no label.
struct MVKSwitch: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .tint(Theme.primary)
    }
}

/// Destructive-tinted inline notice with an icon (web `AlertTriangle` boxes).
struct DestructiveNote: View {
    let text: String
    var icon: String? = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 14)).padding(.top, 1)
            }
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Theme.sans(12))
        .foregroundStyle(Theme.destructive)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.destructive.opacity(0.30), lineWidth: 1))
    }
}

/// The web's `Input`: a bordered field on the background.
struct MVKTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(Theme.sans(14))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.input, lineWidth: 1))
    }
}

extension View {
    /// The web's mobile `DialogContent`: a bottom sheet on `bg-background`
    /// with a `border-t` hairline and the persistent close cross. Padding is
    /// left to the content, as most dialogs override the default `p-6`.
    func mvkDialog(cornerRadius: CGFloat = 0, close: DialogCloseButton.Style = .standard) -> some View {
        modifier(MVKDialogChrome(cornerRadius: cornerRadius, close: close))
    }
}

private struct MVKDialogChrome: ViewModifier {
    let cornerRadius: CGFloat
    let close: DialogCloseButton.Style

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .topTrailing) { DialogCloseButton(style: close) { dismiss() } }
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            .background(Theme.background.ignoresSafeArea())
            .presentationBackground(Theme.background)
            .presentationCornerRadius(cornerRadius)
            .presentationDragIndicator(.hidden)
    }
}
