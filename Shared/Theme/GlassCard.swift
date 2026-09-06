//
//  GlassCard.swift
//  MVK++ Watch App
//

import SwiftUI

/// Full-screen jade gradient behind every list/scroll view — the "greenish,
/// alive" backdrop replacing the flat black default.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.hex("0F241C"), Theme.background, Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// Hides the system list background so `AppBackground` shows through.
    func mvkBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppBackground())
    }

    /// The Liquid Glass card treatment used for rows and info panels.
    func glassCard(tint: Color = Theme.primary, cornerRadius: CGFloat = 16, padding: CGFloat = 10) -> some View {
        self
            .padding(padding)
            .glassEffect(.regular.tint(tint.opacity(0.28)), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
