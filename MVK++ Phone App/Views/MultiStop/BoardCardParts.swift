//
//  BoardCardParts.swift
//  MVK++ Phone App
//

import SwiftUI

/// The shadcn `Card` the Figyelő's cards sit in: rounded, bordered, opaque,
/// with the large shadow. A nearest stop gets a 2 pt primary frame.
struct BoardCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        VStack(spacing: 0, content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.card, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(highlighted ? Theme.primary : Theme.border, lineWidth: highlighted ? 2 : 1))
            .mvkShadow(Theme.Shadow.lg)
    }
}

/// A 1 pt divider in the border colour.
struct HairlineDivider: View {
    var opacity = 1.0

    var body: some View {
        Rectangle().fill(Theme.border.opacity(opacity)).frame(height: 1)
    }
}

/// The ghost icon button in a card header (32 pt, the web's `h-8 w-8`).
/// A destructive one turns red while pressed, like the web's hover.
struct GhostIconButton: View {
    let systemName: String
    let label: String
    var tint: Color = Theme.foreground
    var destructive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(GhostIconStyle(tint: tint, destructive: destructive))
        .accessibilityLabel(label)
    }
}

private struct GhostIconStyle: ButtonStyle {
    let tint: Color
    let destructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(destructive && configuration.isPressed ? Theme.destructive : tint)
            .background(
                configuration.isPressed ? (destructive ? Theme.destructive.opacity(0.15) : Theme.accent) : Color.clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
    }
}

/// The outline icon button (reorder arrows, carousel paging).
struct OutlineIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 32
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(width: size, height: size)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.input, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(label)
    }
}

/// „KÖVETKEZŐ” — the small uppercase label over a card's hero departure.
struct BoardEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(Theme.mutedForeground)
    }
}

/// The right-hand minutes of a list row: „nem jön”, „most”, or „12 p”.
struct RowEta: View {
    let minutes: Int
    var cancelled = false

    var body: some View {
        Group {
            if cancelled {
                Text("nem jön")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.destructive)
            } else if minutes <= 0 {
                Text("most")
                    .font(Theme.mono(16))
                    .foregroundStyle(Theme.live)
            } else {
                let parts = Countdown.parts(minutes: minutes, hours: false)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(parts.value)
                        .font(Theme.mono(16))
                        .foregroundStyle(Theme.foreground)
                    Text(parts.unit == "perc" ? "p" : parts.unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .fixedSize()
    }
}

/// „Járatok lekérése…” and friends: the centred loading or empty line.
struct BoardPlaceholder: View {
    let text: String
    var mono = false

    var body: some View {
        Text(text)
            .font(mono ? Theme.mono(12, weight: .regular) : .system(size: 14))
            .foregroundStyle(Theme.mutedForeground)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

/// Polls while on screen and again on returning to the foreground — the web
/// app's `useVisiblePoll`, for cards that have no WebSocket topic.
struct VisiblePoll: ViewModifier {
    let id: String
    let interval: Duration
    let action: () async -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isTabActive) private var isTabActive

    func body(content: Content) -> some View {
        content
            .task(id: "\(id)|\(isTabActive)") {
                guard isTabActive else { return }
                while !Task.isCancelled {
                    if scenePhase == .active { await action() }
                    try? await Task.sleep(for: interval)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, isTabActive { Task { await action() } }
            }
    }
}

extension View {
    func visiblePoll(id: String, every interval: Duration, _ action: @escaping () async -> Void) -> some View {
        modifier(VisiblePoll(id: id, interval: interval, action: action))
    }
}
