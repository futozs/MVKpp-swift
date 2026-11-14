//
//  MVKControls.swift
//  MVK++ Phone App
//

import SwiftUI

/// The web's shadcn `Button` variants (`components/ui/button.tsx`).
struct MVKButtonStyle: ButtonStyle {
    enum Variant { case primary, outline, ghost, destructive }
    enum Size { case regular, small, large }

    var variant: Variant = .primary
    var size: Size = .regular
    var fullWidth = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        return configuration.label
            .font(.system(size: size == .small ? 12 : 14, weight: .medium))
            .labelStyle(MVKButtonLabelStyle())
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .small ? 12 : (size == .large ? 32 : 16))
            .frame(height: size == .small ? 32 : (size == .large ? 40 : 36))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background(pressed: configuration.isPressed), in: shape)
            .overlay {
                if variant == .outline { shape.strokeBorder(Theme.input, lineWidth: 1) }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch variant {
        case .primary: return Theme.primaryForeground
        case .destructive: return Theme.destructiveForeground
        case .outline, .ghost: return Theme.foreground
        }
    }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .primary: return Theme.primary.opacity(pressed ? 0.9 : 1)
        case .destructive: return Theme.destructive.opacity(pressed ? 0.9 : 1)
        case .outline: return pressed ? Theme.accent : Theme.background
        case .ghost: return pressed ? Theme.accent : .clear
        }
    }
}

private struct MVKButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 14, weight: .medium))
            configuration.title
        }
    }
}

extension ButtonStyle where Self == MVKButtonStyle {
    static func mvk(_ variant: MVKButtonStyle.Variant = .primary, size: MVKButtonStyle.Size = .regular, fullWidth: Bool = false) -> MVKButtonStyle {
        MVKButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}

/// The web dialog's header: icon, title, description, a hairline below.
struct SheetHeader: View {
    let icon: String?
    let title: String
    var subtitle: String?
    var onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            Spacer(minLength: 0)
            if let onClose {
                SheetCloseButton(action: onClose)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// The dialogs' close control: a small glass circle with a muted cross.
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.glassTint).interactive(), in: Circle())
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
            .font(.system(size: 11, weight: .semibold))
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
        .font(.system(size: 12))
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
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.input, lineWidth: 1))
    }
}

extension View {
    /// Sheet chrome shared by the shell's dialogs: dark background and a drag indicator.
    func mvkSheet() -> some View {
        self
            .presentationBackground(Theme.background)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Theme.Radius.xxl)
    }
}
