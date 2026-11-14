//
//  ParkingScreen.swift
//  MVK++ Phone App
//

import SwiftUI

/// Parkoló: who stands at which terminus, and who rests in the depot (web
/// `ParkingView`). Live over the `parking` topic, polled only as a fallback.
struct ParkingScreen: View {
    enum KindFilter: String, Hashable { case all, bus, tram }
    enum Mode: String, Hashable { case lots, blocks }

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject private var local = LocalStore.shared
    @ObservedObject private var realtime = RealtimeClient.shared
    @StateObject private var model = ParkingModel()

    @State private var kind: KindFilter = .all
    @State private var query = ""
    @State private var selected: ParkingSelection?
    @State private var routesByShort: [String: Route] = [:]

    private static let favoritesKey = "mvk_parking_favorites"
    private static let modeKey = "mvk_parking_mode"
    /// Volán and rail in the Parkoló (by default only MVK's fleet shows).
    private static let regionalKey = "mvk_pref_parking_regional"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40 + 90)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        // A vehicle that left the snapshot closes its card rather than blanking it.
        .onReceive(model.$data) { data in
            guard let id = selected?.id else { return }
            if data.flatMap({ ParkingLocated.locate($0, id: id) }) == nil { selected = nil }
        }
        .task(id: store.routes.count) { routesByShort = Self.routesByShort(store.routes) }
        .sheet(item: $selected) { selection in
            if let data = model.data {
                ParkingVehicleSheet(snap: data, id: selection.id, now: model.now, lookup: lookup) { id in
                    navigation.focusVehicleOnMap(id, vehicle: store.vehicle(id: id))
                }
            }
        }
    }

    // MARK: - Preferences

    private var mode: Mode {
        local.json(Self.modeKey, as: String.self).flatMap(Mode.init(rawValue:)) ?? .lots
    }

    private var modeBinding: Binding<Mode> {
        Binding(get: { mode }, set: { local.setJSON(Self.modeKey, $0.rawValue) })
    }

    private var favorites: [String] { local.stringList(Self.favoritesKey) }

    private func isFavorite(_ key: String) -> Bool { favorites.contains(key) }

    private func toggleFavorite(_ key: String) {
        let current = favorites
        local.setJSON(Self.favoritesKey, current.contains(key) ? current.filter { $0 != key } : current + [key])
    }

    private var canRegional: Bool {
        let enabled = local.enabledModes
        return enabled.contains(.coach) || enabled.contains(.rail)
    }

    private var regionalOn: Bool { canRegional && local.json(Self.regionalKey, as: Bool.self) == true }

    // MARK: - Route lookup

    /// The web's `new Map(routes.map(…))`: in catalog order, the last route
    /// with a short name wins (the rail categories share theirs).
    private static func routesByShort(_ routes: [String: Route]) -> [String: Route] {
        let catalog = SharedCatalogCache.routes().filter { routes[$0.id] != nil }
        let ordered = catalog.count == routes.count ? catalog : routes.values.sorted { $0.id < $1.id }
        return Dictionary(ordered.map { ($0.short, $0) }, uniquingKeysWith: { _, last in last })
    }

    private var lookup: ParkingRouteLookup {
        let byShort = routesByShort
        return { short in
            guard let short else { return nil }
            return byShort[short] ?? short.split(separator: " ").first.flatMap { byShort[String($0)] }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parkoló")
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(-0.4)
                    HStack(spacing: 8) {
                        if realtime.connected {
                            LiveDot(size: 6)
                        } else {
                            Circle().fill(Theme.mutedForeground.opacity(0.5)).frame(width: 6, height: 6)
                        }
                        Text(realtime.connected ? "élő" : "frissítés 15 mp-enként")
                        if let at = model.data?.at {
                            Text("· \(ParkingFormat.clock(at))").monospacedDigit()
                        }
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.mutedForeground)
                }
                Spacer(minLength: 0)
                ParkingSegmented(options: [(Mode.lots, "Állóhelyek"), (.blocks, "Forda-tábla")], selection: modeBinding)
                    .fixedSize()
            }

            // The type switch and the Volán toggle share a row when they fit; otherwise the toggle wraps below.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    kindPicker.fixedSize(horizontal: true, vertical: false)
                    if canRegional { regionalToggle }
                }
                VStack(alignment: .leading, spacing: 8) {
                    kindPicker
                    if canRegional { regionalToggle }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.mutedForeground)
                TextField("", text: $query, prompt: Text("Rendszám vagy vonal").foregroundStyle(Theme.mutedForeground))
                    .font(query.isEmpty ? .system(size: 13) : Theme.mono(13, weight: .regular))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("Keresés rendszámra vagy vonalra")
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.input, lineWidth: 1))
        }
    }

    private var kindPicker: some View {
        ParkingSegmented(options: [(KindFilter.all, "Mind"), (.bus, "Busz"), (.tram, "Villamos")], selection: $kind, fill: true)
    }

    private var regionalToggle: some View {
        let on = regionalOn
        return Button {
            local.setBool(Self.regionalKey, !on)
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? Theme.primary : Theme.mutedForeground.opacity(0.4))
                    Circle().fill(Theme.card).frame(width: 12, height: 12).padding(2).mvkShadow(Theme.Shadow.xs)
                }
                .frame(width: 28, height: 16)
                .animation(Theme.Motion.fastAnimation, value: on)
                Text("Volán és vonat")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(on ? Theme.foreground : Theme.mutedForeground)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(on ? Theme.primary.opacity(0.10) : Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Theme.primary.opacity(0.5) : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint("A Volán-buszok és a vonatok a megyei autóbusz-állomásokon és pályaudvarokon (a kocsiszín az MVK-é)")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let data = model.data {
            let view = withFavorites(filter(data), query: query)
            let ctx = ParkingLotContext(
                now: model.now,
                midnight: data.midnight,
                limitS: data.limitS,
                lookup: lookup,
                history: { data.fleet[$0] },
                onSelect: { selected = ParkingSelection(id: $0) }
            )
            let empty = view.terminals.isEmpty && !view.depots.contains { !$0.vehicles.isEmpty } && view.nosignal.isEmpty && view.service.isEmpty

            ParkingFleetSummary(counts: sumCounts(data.counts), facts: facts(view, data: data, now: model.now))

            if mode == .blocks {
                ParkingBlockChart(lookup: lookup, kind: kind, query: query) { selected = ParkingSelection(id: $0) }
            } else if empty {
                ParkingEmptyBox(text: "Nincs ilyen jármű.", verticalPadding: 48)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ParkingSectionTitle(title: "Végállomásokon", count: view.terminals.reduce(0) { $0 + $1.vehicles.count })
                    if view.terminals.isEmpty {
                        ParkingEmptyBox(text: "Most egy végállomáson sem parkol senki.")
                    } else {
                        ForEach(view.terminals) { t in
                            ParkingTerminalLotCard(lot: t, ctx: ctx, favorite: isFavorite("t:\(t.name)")) { toggleFavorite("t:\(t.name)") }
                        }
                    }
                    ParkingNoSignalList(vehicles: view.nosignal, now: model.now, limitS: data.limitS, onSelect: { selected = ParkingSelection(id: $0) }, lookup: lookup)
                    if regionalOn {
                        regionalSection(regionalLots(data), ctx: ctx)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    ParkingSectionTitle(title: "Kocsiszínben", count: view.depots.reduce(0) { $0 + $1.vehicles.count })
                    ForEach(view.depots.filter { !$0.vehicles.isEmpty || kind.rawValue == $0.id.rawValue }) { d in
                        ParkingDepotLotCard(lot: d, ctx: ctx, serviceDate: data.serviceDate, favorite: isFavorite("d:\(d.id.rawValue)")) {
                            toggleFavorite("d:\(d.id.rawValue)")
                        }
                    }
                }
            }

            if mode == .lots {
                ParkingServiceList(vehicles: view.service, onSelect: { selected = ParkingSelection(id: $0) }, lookup: lookup)
            }
        } else {
            ParkingEmptyBox(text: model.error ?? "A parkoló betöltése…", verticalPadding: 64)
        }
    }

    private func regionalSection(_ lots: [ParkingTerminalLot], ctx: ParkingLotContext) -> some View {
        var regionalCtx = ctx
        regionalCtx.regional = true
        return VStack(alignment: .leading, spacing: 12) {
            ParkingSectionTitle(title: "Volán és vonat végállomáson", count: lots.reduce(0) { $0 + $1.vehicles.count })
            if lots.isEmpty {
                ParkingEmptyBox(text: "Most egy megyei autóbusz-állomáson vagy pályaudvaron sem áll Volán-busz vagy vonat.", verticalPadding: 24)
            } else {
                ForEach(lots) { t in
                    ParkingTerminalLotCard(lot: t, ctx: regionalCtx, favorite: isFavorite("t:\(t.name)")) { toggleFavorite("t:\(t.name)") }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Filtering

    private func sumCounts(_ c: [String: ParkingKindCounts]) -> ParkingKindCounts {
        let zero = ParkingKindCounts(service: 0, terminus: 0, depot: 0, nosignal: 0, total: 0)
        if kind != .all { return c[kind.rawValue] ?? zero }
        let bus = c["bus"] ?? zero
        let tram = c["tram"] ?? zero
        return ParkingKindCounts(
            service: bus.service + tram.service,
            terminus: bus.terminus + tram.terminus,
            depot: bus.depot + tram.depot,
            nosignal: bus.nosignal + tram.nosignal,
            total: bus.total + tram.total
        )
    }

    /// By type and search: a plate prefix or an exact route number.
    private func filter(_ s: ParkingSnapshot) -> ParkingSnapshot {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let kindOk: (ParkingFleetKind) -> Bool = { kind == .all || $0.rawValue == kind.rawValue }
        let ok: (String, ParkingFleetKind, String?) -> Bool = { id, k, route in
            kindOk(k) && (q.isEmpty || id.lowercased().hasPrefix(q) || route?.lowercased() == q)
        }
        let parked: (ParkingVehicle) -> Bool = { v in
            ok(v.id, v.kind, v.lastRoute) || (!q.isEmpty && v.next?.route.lowercased() == q && kindOk(v.kind))
        }
        var out = s
        out.terminals = s.terminals.map { var t = $0; t.vehicles = t.vehicles.filter(parked); return t }.filter { !$0.vehicles.isEmpty }
        out.depots = s.depots.map { var d = $0; d.vehicles = d.vehicles.filter(parked); return d }
        out.nosignal = s.nosignal.filter(parked)
        out.service = s.service.filter { ok($0.id, $0.kind, $0.route) }
        return out
    }

    /// Favourites first (in the order added), the rest in the server's order.
    /// A favourite terminus shows even when empty — except while searching.
    private func withFavorites(_ s: ParkingSnapshot, query: String) -> ParkingSnapshot {
        let favs = favorites
        guard !favs.isEmpty else { return s }
        let rank: (String) -> Int = { favs.firstIndex(of: $0) ?? Int.max }
        let present = Set(s.terminals.map(\.name))
        let empty: [ParkingTerminalLot] = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? favs.filter { $0.hasPrefix("t:") && !present.contains(String($0.dropFirst(2))) }
                .map { ParkingTerminalLot(name: String($0.dropFirst(2)), lat: 0, lon: 0, vehicles: []) }
            : []
        var out = s
        out.terminals = stableSorted(s.terminals + empty) { rank("t:\($0.name)") }
        out.depots = stableSorted(s.depots) { rank("d:\($0.id.rawValue)") }
        return out
    }

    private func stableSorted<T>(_ items: [T], by key: (T) -> Int) -> [T] {
        items.enumerated()
            .sorted { (key($0.element), $0.offset) < (key($1.element), $1.offset) }
            .map(\.element)
    }

    /// Volán and rail: only the county's termini, by the enabled modes, filtered by the search.
    private func regionalLots(_ data: ParkingSnapshot) -> [ParkingTerminalLot] {
        guard regionalOn, let regional = data.regional, kind != .tram else { return [] }
        let enabled = local.enabledModes
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let compact: (String) -> String = { $0.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "") }
        let keep: (ParkingVehicle) -> Bool = { v in
            let modeOk = TransitModes.feed(ofId: v.id) == .rail ? enabled.contains(.rail) : enabled.contains(.coach)
            return modeOk && (q.isEmpty || compact(TransitModes.displayVehicleId(v.id)).hasPrefix(compact(q)) || v.lastRoute?.lowercased() == q)
        }
        return regional.terminals
            .map { var t = $0; t.vehicles = t.vehicles.filter(keep); return t }
            .filter { !$0.vehicles.isEmpty }
    }

    /// Three facts under the header: who has stood longest, where most stand,
    /// who has rested longest.
    private func facts(_ view: ParkingSnapshot, data: ParkingSnapshot, now: Double) -> [(label: String, value: Text)] {
        var out: [(label: String, value: Text)] = []
        var longest: (id: String, place: String, since: Double)?
        for t in view.terminals {
            for v in t.vehicles {
                if let since = v.since, longest == nil || since < (longest?.since ?? .infinity) {
                    longest = (v.id, t.name, since)
                }
            }
        }
        if let longest {
            out.append(("Legrégebben áll", Text(longest.id).font(Theme.mono(13, weight: .bold)) + Text(" · \(longest.place) · \(ParkingFormat.duration(now - longest.since))")))
        }
        if let busiest = view.terminals.first, busiest.vehicles.count > 1 {
            out.append(("Legtöbben itt", Text("\(busiest.name) · ") + Text("\(busiest.vehicles.count)").font(Theme.mono(13, weight: .bold))))
        }
        var rest: (id: String, days: Int)?
        for d in view.depots {
            for v in d.vehicles {
                let last = v.reason == .notToday ? data.fleet[v.id]?.lastDate : nil
                let days = last.map { ParkingFormat.daysBetween($0, data.serviceDate) } ?? 0
                if days > 1, days > (rest?.days ?? 0) { rest = (v.id, days) }
            }
        }
        if let rest {
            out.append(("Leghosszabb pihenő", Text(rest.id).font(Theme.mono(13, weight: .bold)) + Text(" · \(rest.days). napja nincs kint")))
        }
        return out
    }
}

struct ParkingSelection: Identifiable, Hashable {
    let id: String
}
