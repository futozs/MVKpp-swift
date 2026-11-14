//
//  RouteTile.swift
//  MVK++ Phone App
//

import SwiftUI

/// The colored route-number badge, filled with the GTFS route_color /
/// route_text pair — the web app's `transit/RouteTile`.
struct RouteTile: View {
    enum Size { case small, medium, large }

    let short: String
    let colorHex: String?
    let textHex: String?
    var size: Size = .medium
    /// A train number tile is a pill (`rounded-full` on the web).
    var capsule = false

    var body: some View {
        Text(short)
            .font(Theme.sans(fontSize, weight: .heavy))
            .monospacedDigit()
            .tracking(fontSize * -0.025)
            .lineLimit(1)
            .foregroundStyle(Theme.hex(textHex, fallback: .white))
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: height, maxHeight: height)
            .background(Theme.hex(colorHex))
            .overlay(shape.stroke(.black.opacity(0.25), lineWidth: 2))
            .clipShape(shape)
            .compositingGroup()
            .mvkShadow(Theme.Shadow.sm)
            .fixedSize()
    }

    private var shape: AnyShape {
        capsule
            ? AnyShape(Capsule(style: .continuous))
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fontSize: CGFloat {
        switch size {
        case .small: return 11
        case .medium: return 12
        case .large: return 16
        }
    }

    private var height: CGFloat {
        switch size {
        case .small: return 20
        case .medium: return 24
        case .large: return 36
        }
    }

    private var minWidth: CGFloat {
        switch size {
        case .small: return 30
        case .medium: return 36
        case .large: return 48
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return 6
        case .medium: return 8
        case .large: return 10
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .small, .medium: return Theme.Radius.md
        case .large: return Theme.Radius.lg
        }
    }
}

#Preview {
    HStack(spacing: 10) {
        RouteTile(short: "1", colorHex: "1FB574", textHex: "FFFFFF", size: .large)
        RouteTile(short: "12", colorHex: "E63946", textHex: "FFFFFF")
        RouteTile(short: "IC 582", colorHex: "1E5AA8", textHex: "FFFFFF", size: .large, capsule: true)
        RouteTile(short: "914", colorHex: "2A6FDB", textHex: "FFFFFF", size: .small)
    }
    .padding()
    .background(AppBackground())
}
