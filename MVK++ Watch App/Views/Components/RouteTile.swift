//
//  RouteTile.swift
//  MVK++ Watch App
//

import SwiftUI

/// The colored route-number badge, filled with the GTFS route_color/route_text
/// pair — same visual language as the web app's RouteTile component.
struct RouteTile: View {
    enum Size { case small, medium, large }

    let short: String
    let colorHex: String
    let textHex: String
    var size: Size = .medium

    var body: some View {
        Text(short)
            .font(.system(size: fontSize, weight: .heavy))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.hex(textHex.isEmpty ? "FFFFFF" : textHex))
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minHeight)
            .background(Theme.hex(colorHex.isEmpty ? "888888" : colorHex))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.black.opacity(0.25), lineWidth: 1)
            )
            .compositingGroup()
            .fixedSize()
            .layoutPriority(2)
    }

    /// Long route numbers ("914", "201") shrink instead of widening the
    /// badge — keeps the rest of the card's layout consistent regardless
    /// of how many digits a route happens to have.
    private var lengthScale: CGFloat {
        switch short.count {
        case 0...1: return 1.0
        case 2: return 0.85
        case 3: return 0.72
        default: return 0.62
        }
    }

    private var fontSize: CGFloat {
        let base: CGFloat
        switch size {
        case .small: base = 11
        case .medium: base = 13
        case .large: base = 18
        }
        return base * lengthScale
    }

    private var minHeight: CGFloat {
        switch size {
        case .small: return 18
        case .medium: return 22
        case .large: return 30
        }
    }

    private var horizontalPadding: CGFloat {
        let base: CGFloat
        switch size {
        case .small: base = 5
        case .medium: base = 7
        case .large: base = 10
        }
        return base * lengthScale
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .small: return 5
        case .medium: return 6
        case .large: return 8
        }
    }
}
