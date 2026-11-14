//
//  RouteChipsView.swift
//  MVK++ Phone App
//

import SwiftUI

/// The route picker. Each chip carries its GTFS color and, when the route has
/// vehicles out, a live count — so a rider can tell at a glance which routes
/// are actually running before filtering to one.
///
/// Routes with nothing on the road are dimmed rather than hidden: their
/// absence is information, and they come back when service resumes.
struct RouteChipsView: View {
    let routes: [String: Route]
    let liveVehicles: [LiveVehicle]
    @Binding var selectedRoutes: [String]

    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 62, maximum: 120), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            quickActions

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
                TextField("Járatszám vagy útvonal", text: $query)
                    .font(Theme.sans(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.input, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

            if visibleRoutes.isEmpty {
                Text("Nincs „\(query)” jelzésű járat.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(visibleRoutes) { route in
                        chip(route)
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 6) {
            Button("Csak a futók (\(runningRouteIds.count))") {
                selectedRoutes = runningRouteIds
            }
            .disabled(runningRouteIds.isEmpty)

            Button("Mind") { selectedRoutes = Array(routes.keys) }

            Button("Egy sem") { selectedRoutes = [] }
                .disabled(selectedRoutes.isEmpty)
        }
        .font(Theme.sans(11, weight: .semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.sm))
        .controlSize(.small)
        .tint(Theme.primary)
    }

    private func chip(_ route: Route) -> some View {
        let isOn = selectedRoutes.contains(route.id)
        let liveCount = liveCountByRoute[route.id] ?? 0
        let idle = liveCount == 0

        return Button {
            toggle(route.id)
        } label: {
            HStack(spacing: 5) {
                if !isOn {
                    // A colour tick, so an unselected chip still identifies
                    // its route without shouting.
                    Capsule()
                        .fill(Theme.hex(route.color, fallback: Theme.mutedForeground))
                        .frame(width: 4, height: 12)
                }

                Text(route.short)
                    .font(Theme.sans(12, weight: .bold))
                    .monospacedDigit()

                if liveCount > 0 {
                    Text("\(liveCount)")
                        .font(Theme.mono(10))
                        .foregroundStyle(isOn ? Theme.foreground : Theme.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            isOn ? Color.black.opacity(0.25) : Theme.primary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }
            }
            .foregroundStyle(isOn ? Theme.hex(route.text, fallback: .white) : Theme.foreground)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(
                isOn ? Theme.hex(route.color) : Theme.secondary,
                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(
                        isOn ? Color.black.opacity(0.2) : Theme.border,
                        lineWidth: 1
                    )
            )
            .opacity(!isOn && idle ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.fastAnimation, value: isOn)
        .accessibilityLabel(route.long.isEmpty ? route.short : route.long)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func toggle(_ routeId: String) {
        if let index = selectedRoutes.firstIndex(of: routeId) {
            selectedRoutes.remove(at: index)
        } else {
            selectedRoutes.append(routeId)
        }
    }

    private var liveCountByRoute: [String: Int] {
        liveVehicles.reduce(into: [:]) { counts, vehicle in
            counts[vehicle.routeId, default: 0] += 1
        }
    }

    private var runningRouteIds: [String] {
        liveCountByRoute.keys.filter { routes[$0] != nil }
    }

    /// Sorted the way the numbers are read: by the leading digits first, then
    /// by the whole name. Plain string order would file "101B" between "1" and
    /// "20", and letter-suffixed lines away from the route they belong to.
    private var orderedRoutes: [Route] {
        routes.values.sorted { a, b in
            let na = Self.leadingNumber(a.short)
            let nb = Self.leadingNumber(b.short)
            if na != nb { return na < nb }
            return a.short.compare(b.short, options: [], range: nil, locale: Locale(identifier: "hu_HU")) == .orderedAscending
        }
    }

    /// "1AV" → 1, "101B" → 101, "ZOO" → sorts last.
    private static func leadingNumber(_ short: String) -> Int {
        let digits = short.prefix { $0.isNumber }
        return Int(digits) ?? Int.max
    }

    private var visibleRoutes: [Route] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return orderedRoutes }
        return orderedRoutes.filter {
            $0.short.containsNormalized(needle) || $0.long.containsNormalized(needle)
        }
    }
}
