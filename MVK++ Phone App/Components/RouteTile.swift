//
//  RouteTile.swift
//  MVK++ Phone App
//

import SwiftUI

/// The colored route-number badge, filled with the GTFS route_color /
/// route_text pair. The single most repeated element in the app — every
/// arrival row, vehicle marker and timetable header carries one.
struct RouteTile: View {
    enum Size { case small, medium, large }

    let short: String
    let colorHex: String?
    let textHex: String?
    var size: Size = .medium

    var body: some View {
        Text(short)
            .font(.system(size: fontSize, weight: .heavy))
            .monospacedDigit()
            .tracking(-0.3)
            .lineLimit(1)
            .foregroundStyle(Theme.hex(textHex, fallback: .white))
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: height)
            .background(Theme.hex(colorHex), in: shape)
            .overlay(shape.strokeBorder(.black.opacity(0.25), lineWidth: 1))
            .compositingGroup()
            .fixedSize()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Three-digit route numbers ("914") shrink rather than widening the
    /// badge, so rows stay aligned no matter what the route is called.
    private var lengthScale: CGFloat {
        switch short.count {
        case 0...2: return 1.0
        case 3: return 0.85
        default: return 0.72
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .small: return 11 * lengthScale
        case .medium: return 12 * lengthScale
        case .large: return 16 * lengthScale
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
        case .small: return 6
        case .medium: return Theme.Radius.sm
        case .large: return Theme.Radius.lg
        }
    }
}

#Preview {
    HStack(spacing: 10) {
        RouteTile(short: "1", colorHex: "1FB574", textHex: "FFFFFF", size: .large)
        RouteTile(short: "12", colorHex: "E63946", textHex: "FFFFFF")
        RouteTile(short: "914", colorHex: "2A6FDB", textHex: "FFFFFF", size: .small)
    }
    .padding()
    .background(AppBackground())
}
