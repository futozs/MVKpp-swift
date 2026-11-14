//
//  MapTraffic.swift
//  MVK++ Phone App
//
//  The live congestion layer (`liveTraffic.ts`, `trafficColor.ts`).
//

import Combine
import SwiftUI
import UIKit

/// A congested link as the map draws it (`/engine/traffic/live`).
struct MapTrafficSegment: Decodable, Hashable, Identifiable {
    let from: String
    let to: String
    let fromId: String?
    let toId: String?
    let routes: [String]
    let path: [[Double]]
    let ratio: Double
    let excessS: Double
    let n: Int
    let stuck: Int
    let level: Double
    let lastTs: Double

    var id: String { "\(fromId ?? from)|\(toId ?? to)" }

    private enum CodingKeys: String, CodingKey {
        case from, to, fromId, toId, routes, path, ratio, excessS, n, stuck, level, lastTs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        fromId = try c.decodeIfPresent(String.self, forKey: .fromId)
        toId = try c.decodeIfPresent(String.self, forKey: .toId)
        routes = try c.decodeIfPresent([String].self, forKey: .routes) ?? []
        path = try c.decodeIfPresent([[Double]].self, forKey: .path) ?? []
        ratio = try c.decodeIfPresent(Double.self, forKey: .ratio) ?? 1
        excessS = try c.decodeIfPresent(Double.self, forKey: .excessS) ?? 0
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        stuck = try c.decodeIfPresent(Int.self, forKey: .stuck) ?? 0
        level = try c.decodeIfPresent(Double.self, forKey: .level) ?? 0
        lastTs = try c.decodeIfPresent(Double.self, forKey: .lastTs) ?? 0
    }
}

private struct MapTrafficResponse: Decodable {
    let segments: [MapTrafficSegment]?
}

enum TrafficColor {
    private static let stops: [(Double, (Double, Double, Double))] = [
        (0, (56, 100, 60)),
        (0.35, (38, 100, 54)),
        (0.65, (16, 95, 52)),
        (0.85, (2, 88, 46)),
        (1, (-8, 82, 32)),
    ]

    /// Lemon (slowing) → orange → red → dark red (standing still), for 0…1.
    static func color(_ level: Double) -> Color {
        let (h, s, l) = hsl(level)
        return hslColor(h, s, l)
    }

    static func uiColor(_ level: Double) -> UIColor { UIColor(color(level)) }

    private static func hsl(_ level: Double) -> (Double, Double, Double) {
        let v = min(1, max(0, level))
        for i in 1..<stops.count {
            let (x1, c1) = stops[i]
            if v > x1 { continue }
            let (x0, c0) = stops[i - 1]
            let t = (v - x0) / (x1 - x0)
            let h = c0.0 + (c1.0 - c0.0) * t
            return ((h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360), c0.1 + (c1.1 - c0.1) * t, c0.2 + (c1.2 - c0.2) * t)
        }
        return (352, 82, 32)
    }

    private static func hslColor(_ h: Double, _ s: Double, _ l: Double) -> Color {
        let s = s / 100, l = l / 100
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case 0..<60: (r, g, b) = (c, x, 0)
        case 60..<120: (r, g, b) = (x, c, 0)
        case 120..<180: (r, g, b) = (0, c, x)
        case 180..<240: (r, g, b) = (0, x, c)
        case 240..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return Color(red: r + m, green: g + m, blue: b + m)
    }
}

/// Live congestion, refreshed every 30 s while the layer is on; empty when off.
@MainActor
final class MapTrafficModel: ObservableObject {
    @Published private(set) var segments: [MapTrafficSegment] = []

    private var task: Task<Void, Never>?
    private let pollInterval: Duration = .seconds(30)

    func setEnabled(_ enabled: Bool) {
        task?.cancel()
        task = nil
        segments = []
        guard enabled else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(30))
            }
        }
    }

    private func load() async {
        guard let body: MapTrafficResponse = try? await APIClient.shared.request(path: "/engine/traffic/live") else { return }
        segments = body.segments ?? []
    }

    deinit { task?.cancel() }
}

/// The congestion popup: how slow, and how we know.
struct MapTrafficPopup: View {
    let segment: MapTrafficSegment
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(TrafficColor.color(segment.level)).frame(width: 10, height: 10)
                Text("\(levelText) a forgalom")
                    .font(Theme.sans(13, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bezárás")
            }
            Text("\(segment.from) → \(segment.to)")
                .font(Theme.sans(12.5, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text("\(Text(ratioText).font(Theme.mono(12, weight: .bold)).foregroundStyle(Theme.foreground)) lassabb a szokásosnál (\(Text("+\(excessText)").font(Theme.mono(12, weight: .regular))))")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.mutedForeground)
            Text(meta)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.mutedForeground)
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Theme.popover, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border))
        .mvkShadow(Theme.Shadow.xl)
    }

    private var levelText: String {
        segment.level >= 0.75 ? "Beállt" : segment.level >= 0.4 ? "Torlódik" : "Lassul"
    }

    private var ratioText: String {
        "\(String(format: "%g", segment.ratio).replacingOccurrences(of: ".", with: ","))×"
    }

    private var excessText: String {
        let total = Int(segment.excessS)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private var meta: String {
        let evidence = [
            segment.n > 0 ? "\(segment.n) átért busz" : nil,
            segment.stuck > 0 ? "\(segment.stuck) most bent ragadt" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        let ago = max(0, Int(((RealtimeClient.shared.serverNow - segment.lastTs) / 60).rounded()))
        return "\(evidence) · \(ago > 0 ? "\(ago) perce" : "most") · \(segment.routes.prefix(6).joined(separator: ", "))"
    }
}
