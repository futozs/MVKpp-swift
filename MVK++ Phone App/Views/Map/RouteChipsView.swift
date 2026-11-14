//
//  RouteChipsView.swift
//  MVK++ Phone App
//

import SwiftUI

/// The route picker (`fleet/RouteChips.tsx`). Each chip carries its GTFS
/// color and, when the route has vehicles out, a live count. By default only
/// the routes running now are listed; selected chips always show, first.
struct RouteChipsView: View {
    let routes: [String: Route]
    let liveVehicles: [LiveVehicle]
    @Binding var selectedRoutes: [String]

    @State private var query = ""
    @State private var onlyLive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                    TextField("Járatszám vagy útvonal", text: $query)
                        .font(Theme.sans(12))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Járat keresése")
                }
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .frame(height: 36)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.input))

                onlyLiveToggle
            }

            ScrollView {
                if visibleRoutes.isEmpty {
                    Text(emptyText)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(visibleRoutes) { route in
                            chip(route)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 224)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyText: String {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty ? "Járatok betöltése…" : "Nincs „\(needle)” jelzésű járat."
    }

    private var onlyLiveToggle: some View {
        Button {
            onlyLive.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(onlyLive ? Theme.primary : Theme.mutedForeground.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text("Csak futó (\(liveRouteCount))")
                    .font(Theme.sans(11, weight: .semibold))
            }
            .foregroundStyle(onlyLive ? Theme.primary : Theme.mutedForeground)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(onlyLive ? Theme.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(onlyLive ? Theme.primary : Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityHint("Csak azok a járatok, amelyeken most busz közlekedik")
        .accessibilityAddTraits(onlyLive ? [.isSelected] : [])
    }

    private func chip(_ route: Route) -> some View {
        let isOn = selectedRoutes.contains(route.id)
        let liveCount = liveCountByRoute[route.id] ?? 0
        let idle = liveCount == 0
        let routeText = Theme.hex(route.text, fallback: .white)

        return Button {
            toggle(route.id)
        } label: {
            HStack(spacing: 6) {
                if !isOn {
                    Capsule()
                        .fill(Theme.hex(route.color, fallback: Theme.mutedForeground))
                        .frame(width: 4, height: 12)
                }

                Text(route.short)
                    .font(Theme.sans(12, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.3)

                if liveCount > 0 {
                    Text("\(liveCount)")
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(isOn ? routeText : Theme.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            isOn ? Color.black.opacity(0.25) : Theme.primary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }
            }
            .foregroundStyle(isOn ? routeText : idle ? Theme.mutedForeground : Theme.foreground)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                isOn ? Theme.hex(route.color) : idle ? Color.clear : Theme.secondary,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(
                        isOn ? Theme.hex(route.color) : idle ? Theme.border.opacity(0.5) : Theme.border,
                        lineWidth: 1
                    )
            )
            .overlay {
                if isOn {
                    RoundedRectangle(cornerRadius: Theme.Radius.md - 1, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.2), lineWidth: 1)
                        .padding(1)
                }
            }
            .mvkShadow(isOn ? Theme.Shadow.sm : Theme.Shadow.none)
            .opacity(!isOn && idle ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.fastAnimation, value: isOn)
        .accessibilityLabel(accessibilityName(route))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func accessibilityName(_ route: Route) -> String {
        let name = route.long.isEmpty ? route.short : route.long
        guard let op = route.operatorName, !op.isEmpty else { return name }
        return "\(name) · \(op)"
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

    private var liveRouteCount: Int {
        liveCountByRoute.keys.filter { id in
            routes[id].map { TransitModes.routeMode($0) != .rail } ?? false
        }.count
    }

    /// MVK first, then Volán (the same numbers, e.g. Ózd's 1, must not mix),
    /// trains left to the rail filter. Within a group by number, then by name.
    private var orderedRoutes: [Route] {
        let hu = Locale(identifier: "hu_HU")
        return routes.values
            .filter { TransitModes.routeMode($0) != .rail }
            .sorted { a, b in
                let ga = Self.group(a)
                let gb = Self.group(b)
                if ga != gb { return ga < gb }
                if let na = Self.leadingNumber(a.short), let nb = Self.leadingNumber(b.short), na != nb {
                    return na < nb
                }
                return a.short.compare(b.short, locale: hu) == .orderedAscending
            }
    }

    private static func group(_ route: Route) -> Int {
        switch TransitModes.routeMode(route) {
        case .tram, .bus: return 0
        case .coach: return 1
        case .rail: return 2
        }
    }

    /// JS `parseInt`: the leading digits, nil when there are none.
    private static func leadingNumber(_ short: String) -> Int? {
        Int(short.prefix { $0.isASCII && $0.isNumber })
    }

    private var visibleRoutes: [Route] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let counts = liveCountByRoute
        let list = orderedRoutes.filter { route in
            (needle.isEmpty || route.short.containsNormalized(needle) || route.long.containsNormalized(needle))
                && (!onlyLive || counts[route.id] != nil || selectedRoutes.contains(route.id))
        }
        return list.filter { selectedRoutes.contains($0.id) } + list.filter { !selectedRoutes.contains($0.id) }
    }
}
