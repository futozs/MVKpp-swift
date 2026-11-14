//
//  MapFilterPanel.swift
//  MVK++ Phone App
//

import SwiftUI

/// „Szűrés” (`filter/FilterPanel.tsx`): which vehicles the map shows (routes,
/// pinned plates, mode, Volán unit, train category, movement, delay, distance)
/// and the list of the visible ones. On a phone a drawer from the left.
struct MapFilterPanel: View {
    @Binding var filters: FilterState
    let routes: [String: Route]
    let vehicles: [LiveVehicle]
    let visibleVehicles: [LiveVehicle]
    let hasPosition: Bool
    var onClear: () -> Void
    var onClose: () -> Void
    var onStartGeo: () -> Void
    var onPickVehicle: (LiveVehicle) -> Void

    private enum Tab { case filters, list }

    @State private var tab: Tab = .filters
    @State private var typedId = ""

    private static let radiusOptions: [(Double?, String)] = [(nil, "Mind"), (0.5, "500 m"), (1.5, "1,5 km"), (5, "5 km")]
    private static let railKindLabel = [
        "Sz": "Személy", "IR": "InterRégió", "IC": "InterCity", "S": "Sebes", "G": "Gyors",
        "EC": "EuroCity", "EN": "EuroNight", "RJ": "Railjet", "Pót": "Pótlóbusz",
    ]
    private static let modeShort: [TransitMode: String] = [.tram: "Villamos", .bus: "Busz", .coach: "Volán", .rail: "Vonat"]

    private var enabledModes: [TransitMode] { TransitMode.enabled() }

    private var counts: (operators: [(String, Int)], railKinds: [(String, Int)], modes: [TransitMode: Int]) {
        var ops: [String: Int] = [:]
        var kinds: [String: Int] = [:]
        var modes: [TransitMode: Int] = [:]
        for v in vehicles {
            let r = routes[v.routeId]
            let m = v.transitMode(routes: routes)
            modes[m, default: 0] += 1
            if m == .coach, let op = r?.operatorName, !op.isEmpty { ops[op, default: 0] += 1 }
            if m == .rail { kinds[r?.short ?? v.routeShort, default: 0] += 1 }
        }
        let hu = Locale(identifier: "hu_HU")
        let byCount: ([String: Int]) -> [(String, Int)] = { m in
            m.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.compare($1.key, locale: hu) == .orderedAscending }.map { ($0.key, $0.value) }
        }
        return (byCount(ops), byCount(kinds), modes)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            if tab == .filters {
                ScrollView { filterSections }
            } else {
                vehicleList
            }
            Button {
                onClose()
            } label: {
                Text("\(visibleVehicles.count) jármű a térképen")
            }
            .buttonStyle(.mvk(fullWidth: true))
            .padding(12)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .background(Theme.card)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Szűrés")
                    .font(Theme.sans(16, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.foreground)
                Text("\(Text("\(visibleVehicles.count)").fontWeight(.semibold).foregroundStyle(Theme.foreground)) jármű látszik\(filters.activeCount > 0 ? " · \(filters.activeCount) szűrő" : "")")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
            }
            Spacer(minLength: 8)
            if filters.isActive {
                Button(action: onClear) {
                    Label("Alaphelyzet", systemImage: "arrow.counterclockwise")
                        .font(Theme.sans(12, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Szűrés bezárása")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tabButton(.filters, "Szűrők", filters.activeCount > 0 ? filters.activeCount : nil)
            tabButton(.list, "Járművek", visibleVehicles.count)
        }
        .padding(8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func tabButton(_ id: Tab, _ label: String, _ count: Int?) -> some View {
        let on = tab == id
        return Button {
            withAnimation(Theme.Motion.fastAnimation) { tab = id }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                if let count {
                    Text("\(count)")
                        .font(Theme.mono(10))
                        .padding(.horizontal, 4)
                        .background(on ? Theme.primaryForeground.opacity(0.2) : Theme.primary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(on ? Theme.primaryForeground : Theme.primary)
                }
            }
            .font(Theme.sans(12, weight: .semibold))
            .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(on ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .mvkShadow(on ? Theme.Shadow.sm : Theme.Shadow.none)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Filters

    @ViewBuilder
    private var filterSections: some View {
        let c = counts
        VStack(spacing: 0) {
            section("Járatok", aside: {
                if filters.routes.isEmpty {
                    Text("mind látszik").font(Theme.sans(11)).foregroundStyle(Theme.mutedForeground)
                } else {
                    Button("\(filters.routes.count) kiválasztva · törlés") { filters.routes = [] }
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }) {
                RouteChipsView(routes: routes, liveVehicles: vehicles, selectedRoutes: $filters.routes)
            }

            section("Kiemelt járművek", aside: {
                if !filters.watch.isEmpty {
                    Text("\(filters.watch.count)/\(FilterState.maxWatched)").font(Theme.mono(11, weight: .regular)).foregroundStyle(Theme.mutedForeground)
                }
            }) {
                Text("Csak ezek a rendszámok látszanak, a többi szűrőtől függetlenül.")
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.mutedForeground)
                HStack(spacing: 8) {
                    TextField("Rendszám vagy vonatszám, pl. 1641", text: $typedId)
                        .font(Theme.mono(14, weight: .regular))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addWatch)
                        .onChange(of: typedId) { _, value in
                            let cleaned = value.filter { $0.isLetter || $0.isNumber }.uppercased()
                            if cleaned != value { typedId = cleaned }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.input))
                        .accessibilityLabel("Kiemelendő jármű rendszáma")
                    Button(action: addWatch) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.mvk(size: .icon, height: 40))
                    .disabled(typedId.isEmpty || filters.watch.count >= FilterState.maxWatched)
                    .accessibilityLabel("Kiemelés")
                }
                if !filters.watch.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(filters.watch, id: \.self) { id in
                            Button {
                                filters.watch.removeAll { $0 == id }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(id).font(Theme.mono(12))
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(Theme.primary)
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.primary.opacity(0.35)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(id) kiemelésének levétele")
                        }
                    }
                    HStack(spacing: 12) {
                        Text("A térkép kövesse őket")
                            .font(Theme.sans(13, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        MVKSwitch(isOn: $filters.follow, label: "A térkép kövesse őket")
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            }

            if enabledModes.count > 1 {
                section("Közlekedési mód", aside: {
                    if filters.modes.isEmpty {
                        Text("mind látszik").font(Theme.sans(11)).foregroundStyle(Theme.mutedForeground)
                    } else {
                        clearLink { filters.modes = [] }
                    }
                }) {
                    chipRow(
                        TransitMode.allCases.filter(enabledModes.contains).map { ($0.rawValue, Self.modeShort[$0] ?? $0.rawValue, c.modes[$0] ?? 0) },
                        selected: filters.modes.map(\.rawValue)
                    ) { id in
                        guard let mode = TransitMode(rawValue: id) else { return }
                        if filters.modes.contains(mode) { filters.modes.removeAll { $0 == mode } } else { filters.modes.append(mode) }
                    }
                }
            }

            if enabledModes.contains(.coach), c.operators.count > 1, filters.modes.isEmpty || filters.modes.contains(.coach) {
                section("Volán", aside: {
                    if !filters.operators.isEmpty { clearLink { filters.operators = [] } }
                }) {
                    chipRow(c.operators.map { ($0.0, $0.0, $0.1) }, selected: filters.operators) { toggle(\.operators, $0) }
                }
            }

            if enabledModes.contains(.rail), c.railKinds.count > 1, filters.modes.isEmpty || filters.modes.contains(.rail) {
                section("Vonat", aside: {
                    if !filters.railKinds.isEmpty { clearLink { filters.railKinds = [] } }
                }) {
                    chipRow(c.railKinds.map { ($0.0, Self.railKindLabel[$0.0] ?? $0.0, $0.1) }, selected: filters.railKinds) { toggle(\.railKinds, $0) }
                }
            }

            section("Jármű", aside: { EmptyView() }) {
                segmented("Mozgás", value: filters.speed, options: [(.all, "Mind"), (.moving, "Mozgó"), (.idle, "Álló")]) { filters.speed = $0 }
                segmented("Késés", value: filters.delay, options: [(.all, "Mind"), (.late, "5+ perc"), (.ontime, "Pontos")]) { filters.delay = $0 }
            }

            section("A közelemben", last: true, aside: {
                if !hasPosition {
                    Button(action: onStartGeo) {
                        Label("Helyzetem bekapcsolása", systemImage: "location.fill")
                            .font(Theme.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                }
            }) {
                HStack(spacing: 4) {
                    ForEach(Self.radiusOptions, id: \.1) { value, label in
                        let on = filters.nearMeKm == value
                        Button {
                            filters.nearMeKm = value
                        } label: {
                            Text(label)
                                .font(Theme.sans(12, weight: .semibold))
                                .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .background(on ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                                .mvkShadow(on ? Theme.Shadow.sm : Theme.Shadow.none)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasPosition && value != nil)
                        .opacity(!hasPosition && value != nil ? 0.4 : 1)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border))
            }
        }
    }

    private func addWatch() {
        let id = typedId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, filters.watch.count < FilterState.maxWatched,
              !filters.watch.contains(where: { $0.lowercased() == id.lowercased() }) else { return }
        filters.watch.append(id)
        typedId = ""
    }

    private func toggle(_ key: WritableKeyPath<FilterState, [String]>, _ value: String) {
        if filters[keyPath: key].contains(value) {
            filters[keyPath: key].removeAll { $0 == value }
        } else {
            filters[keyPath: key].append(value)
        }
    }

    private func clearLink(_ action: @escaping () -> Void) -> some View {
        Button("mind", action: action)
            .font(Theme.sans(11, weight: .semibold))
            .foregroundStyle(Theme.primary)
    }

    private func section<Aside: View, Content: View>(
        _ title: String,
        last: Bool = false,
        @ViewBuilder aside: () -> Aside,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(Theme.sans(11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.mutedForeground)
                Spacer(minLength: 8)
                aside()
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }

    private func chipRow(_ items: [(id: String, label: String, count: Int)], selected: [String], onToggle: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(items, id: \.id) { item in
                let on = selected.contains(item.id)
                Button {
                    onToggle(item.id)
                } label: {
                    HStack(spacing: 6) {
                        Text(item.label).font(Theme.sans(12, weight: .semibold))
                        Text("\(item.count)")
                            .font(Theme.mono(10))
                            .padding(.horizontal, 4)
                            .background(on ? Theme.primaryForeground.opacity(0.2) : Theme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(on ? Theme.primary : Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(on ? Theme.primary.opacity(0.4) : Theme.border))
                    .mvkShadow(on ? Theme.Shadow.sm : Theme.Shadow.none)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func segmented<T: Equatable>(_ label: String, value: T, options: [(T, String)], onChange: @escaping (T) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.sans(12, weight: .medium))
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 64, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let on = option.0 == value
                    Button {
                        onChange(option.0)
                    } label: {
                        Text(option.1)
                            .font(Theme.sans(12, weight: .semibold))
                            .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(on ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                            .mvkShadow(on ? Theme.Shadow.sm : Theme.Shadow.none)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border))
        }
    }

    // MARK: Vehicle list

    private var vehicleList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("RENDEZÉS")
                    .font(Theme.sans(11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.mutedForeground)
                ForEach(VehicleSort.allCases, id: \.self) { sort in
                    let on = filters.sort == sort
                    Button(sort.label) { filters.sort = sort }
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 28)
                        .background(on ? Theme.primary : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            if visibleVehicles.isEmpty {
                Text("A jelenlegi szűrésnek egy jármű sem felel meg.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 32)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                List(VehicleFilter.sorted(visibleVehicles, by: filters.sort)) { v in
                    Button {
                        onPickVehicle(v)
                    } label: {
                        HStack(spacing: 12) {
                            RouteTile(short: v.routeShort, colorHex: v.routeColor, textHex: v.routeText)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(title(v)).font(Theme.mono(14)).foregroundStyle(Theme.foreground)
                                    LiveDot()
                                }
                                Text(v.headsign)
                                    .font(Theme.sans(11))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(v.speedKmh.map { "\($0) km/h" } ?? "")
                                .font(Theme.mono(12, weight: .semibold))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                    .listRowSeparatorTint(Theme.border.opacity(0.6))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func title(_ v: LiveVehicle) -> String {
        guard v.mode == .rail else { return TransitIds.displayVehicleId(v.id, plate: v.plate) }
        let text = "\(v.trainNo ?? "")\(v.trainName.map { " \($0)" } ?? "")".trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "Vonat" : text
    }
}

enum MapFilterSummary {
    private static let modeShort: [TransitMode: String] = [.tram: "villamos", .bus: "busz", .coach: "volán", .rail: "vonat"]

    private static func radius(_ km: Double) -> String {
        km < 1 ? "\(Int((km * 1000).rounded())) m" : "\(String(format: "%g", km).replacingOccurrences(of: ".", with: ",")) km"
    }

    /// One line for the top of the map (e.g. „14, 34 · mozgó · 12 jármű”).
    static func text(_ f: FilterState, routes: [String: Route], visible: Int) -> String {
        if !f.watch.isEmpty { return "\(f.watch.joined(separator: ", ")) · \(visible) jármű" }
        var parts: [String] = []
        if !f.routes.isEmpty {
            let names = f.routes.map { routes[$0]?.short ?? $0 }
            parts.append(names.count > 3 ? "\(names.prefix(3).joined(separator: ", ")) +\(names.count - 3)" : names.joined(separator: ", "))
        }
        if !f.modes.isEmpty { parts.append(f.modes.map { modeShort[$0] ?? $0.rawValue }.joined(separator: ", ")) }
        if !f.operators.isEmpty { parts.append(f.operators.count > 2 ? "\(f.operators.count) Volán-egység" : f.operators.joined(separator: ", ")) }
        if !f.railKinds.isEmpty { parts.append(f.railKinds.joined(separator: ", ")) }
        if f.delay != .all { parts.append(f.delay == .late ? "késik" : "pontos") }
        if f.speed != .all { parts.append(f.speed == .moving ? "mozgó" : "álló") }
        if let km = f.nearMeKm { parts.append("\(radius(km))-en belül") }
        parts.append("\(visible) jármű")
        return parts.joined(separator: " · ")
    }
}
