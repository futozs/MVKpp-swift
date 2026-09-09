//
//  Theme.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import SwiftUI

/// Design tokens ported 1:1 from the web app's `theme/tokens.css`, kept as the
/// same HSL triples so every MVK++ surface — web, watch, phone, widget — reads
/// as one product.
///
/// Semantic colors carry meaning, not decoration: live/ontime = green,
/// late = red-orange, early = blue. Never reuse them for emphasis.
enum Theme {

    // MARK: - shadcn base scale

    static let background = hsl(165, 18, 4.3)
    static let foreground = hsl(146, 18, 92.4)

    static let card = hsl(160, 16, 7.5)
    static let cardForeground = foreground

    static let popover = hsl(163, 15, 9.2)
    static let popoverForeground = foreground

    static let primary = hsl(154, 71, 41.6)
    static let primaryForeground = hsl(155, 79, 9.4)

    static let secondary = hsl(160, 15, 12)
    static let secondaryForeground = hsl(147, 16, 86.5)

    static let muted = secondary
    static let mutedForeground = hsl(153, 9, 61.6)

    static let accent = hsl(158, 14, 15.9)
    static let accentForeground = foreground

    static let destructive = hsl(9, 86, 58.8)
    static let destructiveForeground = hsl(10, 71, 9.6)

    static let border = accent
    static let input = hsl(160, 14, 17.3)
    static let ring = hsl(153, 59, 50.2)

    // MARK: - Semantic signals

    /// The data is arriving in real time from the vehicle.
    static let live = hsl(153, 59, 50.2)
    static let ontime = live
    /// Behind schedule.
    static let late = hsl(9, 86, 58.8)
    /// Ahead of schedule.
    static let early = hsl(208, 83, 64.7)
    /// Nothing is reporting: the gateway is unreachable and what is on
    /// screen was read off the device. Amber, because it is neither an error
    /// nor good news — the times are real, they are just not being checked.
    static let offline = hsl(38, 92, 60)

    // MARK: - Green scale (`--sg-*`)

    static let signal50 = hsl(150, 69, 94.9)
    static let signal100 = hsl(151, 69, 87.5)
    static let signal200 = hsl(152, 68, 75.5)
    static let signal300 = hsl(153, 64, 61.8)
    static let signal400 = hsl(153, 59, 50.2)
    static let signal500 = hsl(154, 71, 41.6)
    static let signal600 = hsl(155, 75, 33.5)
    static let signal700 = hsl(155, 74, 27.1)
    static let signal800 = hsl(156, 69, 21.8)
    static let signal900 = hsl(158, 67, 16.7)
    static let signal950 = hsl(158, 75, 9.4)

    // MARK: - Radii (`--radius: 0.75rem` = 12pt)

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        /// Sheets and full-bleed cards.
        static let xxl: CGFloat = 20
    }

    // MARK: - Motion

    enum Motion {
        static let fast: TimeInterval = 0.15
        static let normal: TimeInterval = 0.24
        /// `cubic-bezier(0.22, 1, 0.36, 1)` — the web app's single easing curve.
        static let easeOut = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.22, y: 1),
            endControlPoint: UnitPoint(x: 0.36, y: 1)
        )

        static var fastAnimation: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: fast) }
        static var normalAnimation: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: normal) }
    }

    // MARK: - Depth
    //
    // The web tokens layer two shadows per level; SwiftUI takes one, so each
    // level below is the dominant (larger) of the pair.

    enum Shadow {
        static let color = Color(hue: 160.0 / 360, saturation: 0.40, brightness: 0.02)

        struct Level {
            let radius: CGFloat
            let y: CGFloat
            let opacity: Double
        }

        static let xs = Level(radius: 2, y: 1, opacity: 0.50)
        static let sm = Level(radius: 3, y: 1, opacity: 0.50)
        static let md = Level(radius: 12, y: 4, opacity: 0.55)
        static let lg = Level(radius: 24, y: 10, opacity: 0.65)
        static let xl = Level(radius: 48, y: 20, opacity: 0.75)
    }

    // MARK: - Type
    //
    // The web app pairs Plus Jakarta Sans with JetBrains Mono. On Apple
    // platforms the closest system equivalents are SF Pro Rounded (the same
    // geometric-humanist, rounded feel) and SF Mono. Both ship with the OS,
    // so there is no font payload and Dynamic Type keeps working.

    /// Every numeric readout — countdown, vehicle ID, speed, delay — so digits
    /// never jump as they tick.
    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Helpers

    /// Route tile colors come from GTFS as bare hex (no "#"). Falls back to
    /// the brand green for missing/malformed values, matching the web app's
    /// `api.ts` normalization.
    static func hex(_ value: String?, fallback: Color = Color(red: 0.122, green: 0.710, blue: 0.455)) -> Color {
        guard let value else { return fallback }
        let sanitized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let rgb = UInt64(sanitized, radix: 16) else { return fallback }
        return Color(
            red: Double((rgb & 0xFF0000) >> 16) / 255,
            green: Double((rgb & 0x00FF00) >> 8) / 255,
            blue: Double(rgb & 0x0000FF) / 255
        )
    }

    private static func hsl(_ h: Double, _ s: Double, _ l: Double) -> Color {
        let s = s / 100
        let l = l / 100
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case 0..<60: (r1, g1, b1) = (c, x, 0)
        case 60..<120: (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return Color(red: r1 + m, green: g1 + m, blue: b1 + m)
    }
}

extension View {
    /// Applies one of the web app's five depth levels.
    func mvkShadow(_ level: Theme.Shadow.Level) -> some View {
        shadow(
            color: Theme.Shadow.color.opacity(level.opacity),
            radius: level.radius / 2,
            x: 0,
            y: level.y
        )
    }
}
