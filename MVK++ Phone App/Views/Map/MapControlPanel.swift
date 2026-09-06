//
//  MapControlPanel.swift
//  MVK++ Phone App
//

import CoreLocation
import SwiftUI

/// The map's control drawer: what to show, which vehicles are out, and which
/// stop to jump to. On the web this is a permanent left sidebar; on a phone it
/// is a sheet, so the map keeps the whole screen until the rider asks for it.
struct MapControlPanel: View {

    enum Section: String, CaseIterable, Identifiable {
        case filter, fleet, stops
        var id: String { rawValue }

        var title: String {
            switch self {
            case .filter: return "Szűrés"
            case .fleet: return "Járművek"
            case .stops: return "Megállók"
            }
        }
    }

    let routes: [String: Route]
    let vehicles: [LiveVehicle]
    let stops: [Stop]
    let visibleVehicles: [LiveVehicle]
    let monitoredStopIds: [String]
    let selectedStopId: String?

    @Binding var filters: FilterState

    var onOpenBaseMap: () -> Void
    var onFlyToVehicle: (LiveVehicle) -> Void
    var onSelectStop: (Stop) -> Void
    var onFlyTo: (CLLocationCoordinate2D) -> Void
    var onToggleMonitorStop: (String) -> Void

    @EnvironmentObject private var location: LocationProvider
    @Environment(\.dismiss) private var dismiss

    @State private var section: Section = .filter
    @State private var typedId = ""
    @State private var stopQuery = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Nézet", selection: $section) {
                    ForEach(Section.allCases) { section in
                        Text(section == .fleet ? "\(section.title) (\(visibleVehicles.count))" : section.title)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Divider().overlay(Theme.border)

                switch section {
                case .filter: filterSection
                case .fleet: fleetSection
                case .stops: stopsSection
                }
            }
            .background(AppBackground())
            .navigationTitle("Térkép")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kész") { dismiss() }
                }
            }
        }
    }

    // MARK: - Filter

    private var filterSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Following one specific vehicle is the most common reason to
                // open this panel, so it sits at the top.
                panelSection(
                    "Jármű követése",
                    trailing: filters.watch.isEmpty ? nil : "\(filters.watch.count)/\(FilterState.maxWatched)"
                ) {
                    watchControls
                }

                panelSection("Mit mutasson") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Típus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.mutedForeground)
                            Picker("Típus", selection: $filters.type) {
                                ForEach(VehicleTypeFilter.allCases, id: \.self) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mozgás")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.mutedForeground)
                            Picker("Mozgás", selection: $filters.speed) {
                                ForEach(SpeedFilter.allCases, id: \.self) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                panelSection("A közelemben", accessory: {
                    if location.position == nil {
                        Button("GPS bekapcsolása") { location.start() }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.primary)
                    }
                }) {
                    radiusChips
                }

                panelSection(
                    "Járatok",
                    trailing: filters.routes.isEmpty ? "mind" : "\(filters.routes.count) kiválasztva"
                ) {
                    RouteChipsView(
                        routes: routes,
                        liveVehicles: vehicles,
                        selectedRoutes: $filters.routes
                    )
                }

                panelSection("Megjelenítés", isLast: true) {
                    VStack(spacing: 2) {
                        toggleRow("Megállók", isOn: $filters.stops)
                        toggleRow("Csak a figyeltek (\(monitoredStopIds.count))", isOn: $filters.onlyWatched)
                        toggleRow("Járatnyomvonal", isOn: $filters.shape)
                        toggleRow("Rendszámok a csempéken", isOn: $filters.labels)

                        Button {
                            onOpenBaseMap()
                        } label: {
                            Label("Alaptérkép", systemImage: "square.3.layers.3d")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.foreground)
                        .background(Theme.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .padding(.top, 8)
                    }
                }

                if filters.isActive {
                    Button("Szűrők törlése") { filters = .default }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.destructive)
                        .padding(16)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var watchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Rendszám, pl. 1641", text: $typedId)
                    .font(Theme.mono(15, weight: .semibold))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Theme.input, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .onChange(of: typedId) { _, value in
                        let digits = value.filter(\.isNumber)
                        if digits != value { typedId = digits }
                        filters.vq = digits
                    }

                Button {
                    addWatch()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.primary)
                .disabled(typedId.isEmpty || filters.watch.count >= FilterState.maxWatched)
            }

            if !filters.watch.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(filters.watch, id: \.self) { id in
                        Button {
                            filters.watch.removeAll { $0.lowercased() == id.lowercased() }
                        } label: {
                            HStack(spacing: 5) {
                                Text(id).font(Theme.mono(12))
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                    .strokeBorder(Theme.primary.opacity(0.35), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(id) eltávolítása a követésből")
                    }
                }
            }

            toggleRow("Térkép kövesse a járművet", isOn: $filters.follow)
        }
    }

    private var radiusChips: some View {
        let options: [(Double?, String)] = [
            (nil, "Nincs"), (0.5, "500 m"), (1.5, "1,5 km"), (5, "5 km"),
        ]

        return FlowLayout(spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
                let (value, label) = options[index]
                let isOn = filters.nearMeKm == value
                Button(label) { filters.nearMeKm = value }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.primaryForeground : Theme.mutedForeground)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        isOn ? Theme.primary : Theme.secondary,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    )
                    .buttonStyle(.plain)
                    // A radius means nothing without a fix to measure from.
                    .disabled(location.position == nil && value != nil)
                    .opacity(location.position == nil && value != nil ? 0.4 : 1)
            }
        }
    }

    // MARK: - Fleet

    private var fleetSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("RENDEZÉS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.mutedForeground)

                Picker("Rendezés", selection: $filters.sort) {
                    ForEach(VehicleSort.allCases, id: \.self) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().overlay(Theme.border)

            if sortedVehicles.isEmpty {
                ContentUnavailableView(
                    "Nincs találat",
                    systemImage: "bus",
                    description: Text("A jelenlegi szűrésnek egy jármű sem felel meg.")
                )
            } else {
                List(sortedVehicles) { vehicle in
                    Button {
                        onFlyToVehicle(vehicle)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            RouteTile(short: vehicle.routeShort, colorHex: vehicle.routeColor, textHex: vehicle.routeText)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(vehicle.id).font(Theme.mono(14))
                                    LiveDot(size: 7)
                                }
                                Text(vehicle.headsign)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Text(vehicle.speedKmh.map { "\($0) km/h" } ?? "—")
                                .font(Theme.mono(12, weight: .semibold))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.border)
                }
                .listStyle(.plain)
                .mvkBackground()
            }
        }
    }

    private var sortedVehicles: [LiveVehicle] {
        VehicleFilter.sorted(visibleVehicles, by: filters.sort)
    }

    // MARK: - Stops

    /// GTFS lists one row per platform, so a junction like "Villanyrendőr"
    /// would appear a dozen times. Results are grouped by name; picking a
    /// multi-platform group just moves the map there, and the rider taps the
    /// dot they actually want.
    private struct StopGroup: Identifiable {
        let name: String
        let stops: [Stop]
        let center: CLLocationCoordinate2D
        var id: String { name }
    }

    private var stopsSection: some View {
        Group {
            if stopGroups.isEmpty {
                ContentUnavailableView.search(text: stopQuery)
            } else {
                List(stopGroups) { group in
                    HStack(spacing: 8) {
                        Button {
                            if let single = group.stops.count == 1 ? group.stops[0] : nil {
                                onSelectStop(single)
                            } else {
                                onFlyTo(group.center)
                            }
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.foreground)
                                    .lineLimit(1)
                                Text(group.stops.count == 1 ? group.stops[0].id : "\(group.stops.count) megálló")
                                    .font(Theme.mono(11, weight: .regular))
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if group.stops.count == 1 {
                            let stopId = group.stops[0].id
                            let watched = monitoredStopIds.contains(stopId)
                            Button {
                                onToggleMonitorStop(stopId)
                            } label: {
                                Image(systemName: watched ? "checkmark" : "plus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(watched ? Theme.primaryForeground : Theme.foreground)
                            .background(
                                watched ? Theme.primary : Theme.secondary,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            )
                            .accessibilityLabel(watched ? "\(group.name) levétele a figyelőről" : "\(group.name) felvétele a figyelőre")
                        }
                    }
                    .listRowBackground(
                        group.stops.contains { $0.id == selectedStopId }
                            ? Theme.primary.opacity(0.10)
                            : Color.clear
                    )
                    .listRowSeparatorTint(Theme.border)
                }
                .listStyle(.plain)
                .mvkBackground()
            }
        }
        .searchable(text: $stopQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Megálló neve vagy kódja")
    }

    private var stopGroups: [StopGroup] {
        let needle = stopQuery.trimmingCharacters(in: .whitespaces)
        let source = needle.isEmpty ? stops : stops.filter { $0.matches(needle) }

        var byName: [String: [Stop]] = [:]
        for stop in source { byName[stop.name, default: []].append(stop) }

        return byName
            .map { name, group in
                StopGroup(
                    name: name,
                    stops: group,
                    center: CLLocationCoordinate2D(
                        latitude: group.reduce(0) { $0 + $1.lat } / Double(group.count),
                        longitude: group.reduce(0) { $0 + $1.lon } / Double(group.count)
                    )
                )
            }
            .sorted {
                $0.name.compare($1.name, options: [], range: nil, locale: Locale(identifier: "hu_HU")) == .orderedAscending
            }
            .prefix(80)
            .map { $0 }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func panelSection<Content: View, Accessory: View>(
        _ title: String,
        trailing: String? = nil,
        isLast: Bool = false,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.mutedForeground)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(Theme.mono(11, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                }
                accessory()
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Theme.border).frame(height: 1)
            }
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .font(.system(size: 13, weight: .medium))
            .tint(Theme.primary)
            .padding(.vertical, 4)
    }

    private func addWatch() {
        let target = typedId.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty, filters.watch.count < FilterState.maxWatched else { return }
        guard !filters.watch.contains(where: { $0.lowercased() == target.lowercased() }) else { return }
        filters.watch.append(target)
        filters.vq = ""
        typedId = ""
    }
}
