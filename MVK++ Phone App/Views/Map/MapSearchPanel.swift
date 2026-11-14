//
//  MapSearchPanel.swift
//  MVK++ Phone App
//

import CoreLocation
import SwiftUI

/// „Keresés” (bottom left, `controls/MapSearch.tsx`): a stop's name or the
/// code on its sign, a bus's plate or a train's number — in one field.
/// Empty, it lists the stops nearby.
struct MapSearchPanel: View {
    let stops: [Stop]
    let vehicles: [LiveVehicle]
    let position: GeoPosition?
    let monitoredStopIds: [String]
    let watched: [String]
    var onToggleMonitorStop: (String) -> Void
    var onPickStop: (Stop) -> Void
    var onPickPlace: (CLLocationCoordinate2D) -> Void
    var onPickVehicle: (LiveVehicle) -> Void
    var onToggleWatch: (String) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Bool

    private static let maxStops = 40
    private static let maxVehicles = 8
    private static let nearKm = 0.6

    private struct StopGroup: Identifiable {
        let name: String
        let group: [Stop]
        let lat: Double
        let lon: Double
        let km: Double?
        var id: String { name }
    }

    private var term: String { query.trimmingCharacters(in: .whitespaces).normalizedForSearch }
    private var raw: String { query.trimmingCharacters(in: .whitespaces) }
    private var digits: String? { !raw.isEmpty && raw.allSatisfy(\.isNumber) ? raw : nil }

    private var byCode: Stop? {
        guard let digits else { return nil }
        return stops.first { $0.id.lowercased() == "sp\(digits)" }
    }

    private var pickable: [Stop] {
        let ids = Set(stops.map(\.id))
        return stops.filter { !($0.parent.map { !$0.isEmpty && ids.contains($0) } ?? false) }
    }

    private var groups: [StopGroup] {
        let source: [Stop]
        if !term.isEmpty {
            source = pickable.filter { $0.name.normalizedForSearch.contains(term) || (!$0.code.isEmpty && $0.code.normalizedForSearch == term) }
        } else if let position {
            source = pickable.filter { Geo.distanceKm(position.lat, position.lon, $0.lat, $0.lon) <= Self.nearKm }
        } else {
            source = []
        }
        var byName: [String: [Stop]] = [:]
        var order: [String] = []
        for s in source {
            if byName[s.name] == nil { order.append(s.name) }
            byName[s.name, default: []].append(s)
        }
        var out = order.compactMap { name -> StopGroup? in
            guard let group = byName[name], !group.isEmpty else { return nil }
            let lat = group.map(\.lat).reduce(0, +) / Double(group.count)
            let lon = group.map(\.lon).reduce(0, +) / Double(group.count)
            return StopGroup(name: name, group: group, lat: lat, lon: lon, km: position.map { Geo.distanceKm($0.lat, $0.lon, lat, lon) })
        }
        let hu = Locale(identifier: "hu_HU")
        if term.isEmpty {
            out.sort { ($0.km ?? 0) < ($1.km ?? 0) }
        } else {
            out.sort {
                let ra = MapRegion.rank($0.group[0]), rb = MapRegion.rank($1.group[0])
                return ra != rb ? ra < rb : $0.name.compare($1.name, locale: hu) == .orderedAscending
            }
        }
        return Array(out.prefix(Self.maxStops))
    }

    private static func compact(_ t: String) -> String {
        t.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").uppercased()
    }

    private func matches(_ v: LiveVehicle) -> Bool {
        let mode = TransitIds.vehicleMode(id: v.id, mode: v.mode, label: v.label)
        switch mode {
        case .rail:
            guard let digits, digits.count >= 2 else { return false }
            return v.trainNo?.hasPrefix(digits) == true
        case .coach:
            let q = Self.compact(raw)
            return q.count >= 2 && q.allSatisfy { $0.isLetter || $0.isNumber } && Self.compact(TransitIds.displayVehicleId(v.id, plate: v.plate)).contains(q)
        default:
            guard let digits else { return false }
            return v.id.contains(digits)
        }
    }

    private var vehicleHits: [LiveVehicle] {
        guard !raw.isEmpty else { return [] }
        return Array(vehicles.filter(matches).sorted { $0.id.count < $1.id.count }.prefix(Self.maxVehicles))
    }

    private static func vehicleTitle(_ v: LiveVehicle) -> String {
        if TransitIds.vehicleMode(id: v.id, mode: v.mode, label: v.label) == .rail, let no = v.trainNo {
            return "\(no)\(v.trainName.map { " \($0)" } ?? "")"
        }
        return TransitIds.displayVehicleId(v.id, plate: v.plate)
    }

    private static func stopSub(_ s: Stop) -> String {
        TransitIds.isRegional(s.id)
            ? StopKind.label(stopId: s.id, isStation: s.station == true)
            : "kód \(s.id.replacingOccurrences(of: "SP", with: "", options: [.caseInsensitive, .anchored]))"
    }

    var body: some View {
        let groups = self.groups
        let hits = vehicleHits
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.mutedForeground)
                    TextField("Megálló, kód, rendszám vagy vonatszám", text: $query)
                        .font(.system(size: 15))
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await submit(groups: groups, hits: hits) } }
                        .onChange(of: query) { _, _ in error = nil }
                        .accessibilityLabel("Megálló neve, megállókód, rendszám vagy vonatszám")
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.input))

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bezárás")
            }
            .padding(10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.destructive)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }

                    if let byCode, let digits {
                        section("Megállókód") {
                            stopRow(name: byCode.name, sub: "\(digits). számú megálló", multi: false, watched: monitoredStopIds.contains(byCode.id)) {
                                onPickStop(byCode)
                                close()
                            } onToggleWatch: {
                                onToggleMonitorStop(byCode.id)
                            }
                        }
                    }

                    if !hits.isEmpty {
                        section("Járművek") {
                            ForEach(hits) { v in vehicleRow(v) }
                        }
                    }

                    if !groups.isEmpty {
                        section(term.isEmpty ? "A közeledben" : "Megállók") {
                            ForEach(groups) { g in
                                let single = g.group.count == 1 ? g.group[0] : nil
                                let sub = [single.map { Self.stopSub($0) } ?? "\(g.group.count) kocsiállás", g.km.map(Geo.formatDistance)]
                                    .compactMap { $0 }.joined(separator: " · ")
                                stopRow(name: g.name, sub: sub, multi: single == nil, watched: single.map { monitoredStopIds.contains($0.id) }) {
                                    pickGroup(g)
                                } onToggleWatch: {
                                    if let single { onToggleMonitorStop(single.id) }
                                }
                            }
                        }
                    }

                    if !term.isEmpty, byCode == nil, groups.isEmpty, hits.isEmpty {
                        note(busy ? "Keresés…" : digits.map { "Nincs ilyen rendszámú jármű vagy \($0) kódú megálló a listában Enterrel a szervertől is megkérdezem." } ?? "Nincs „\(raw)” nevű megálló.")
                    }
                    if term.isEmpty, groups.isEmpty {
                        note("Írd be a megálló nevét, a táblán látható kódját, egy busz rendszámát vagy egy vonat számát.")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Theme.card)
        .onAppear { focused = true }
    }

    private func close() {
        query = ""
        error = nil
        onClose()
    }

    private func pickGroup(_ g: StopGroup) {
        if g.group.count == 1 {
            onPickStop(g.group[0])
        } else {
            onPickPlace(CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon))
        }
        close()
    }

    private func submit(groups: [StopGroup], hits: [LiveVehicle]) async {
        if let byCode {
            onPickStop(byCode)
            close()
        } else if hits.count == 1 {
            onPickVehicle(hits[0])
            close()
        } else if groups.count == 1 {
            pickGroup(groups[0])
        } else {
            await lookupCode()
        }
    }

    /// A code missing from the loaded list: the server may still know it.
    private func lookupCode() async {
        guard let digits, byCode == nil else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let response = try await APIClient.shared.arrivals(stopId: "SP\(digits)", limit: 1)
            let s = response.stop
            if let lat = s.lat, let lon = s.lon {
                onPickStop(Stop(id: s.id, code: s.code ?? digits, name: s.name ?? "SP\(digits)", lat: lat, lon: lon))
                close()
            } else {
                error = "Nincs \(digits) kódú megálló."
            }
        } catch {
            self.error = "Nincs \(digits) kódú megálló."
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            content()
        }
        .padding(.vertical, 4)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.mutedForeground)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
    }

    private func stopRow(name: String, sub: String, multi: Bool, watched: Bool?, onPick: @escaping () -> Void, onToggleWatch: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button(action: onPick) {
                HStack(spacing: 12) {
                    Image(systemName: multi ? "mappin.and.ellipse" : "bus")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 32, height: 32)
                        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        Text(sub)
                            .font(Theme.mono(11, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let watched {
                Button(action: onToggleWatch) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .rotationEffect(.degrees(watched ? 45 : 0))
                        .foregroundStyle(watched ? Theme.primary : Theme.mutedForeground)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                        .animation(Theme.Motion.fastAnimation, value: watched)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(watched ? "\(name) levétele a figyelőről" : "\(name) felvétele a figyelőre")
            }
        }
        .padding(.trailing, 8)
    }

    private func vehicleRow(_ v: LiveVehicle) -> some View {
        let on = watched.contains(v.id)
        return HStack(spacing: 4) {
            Button {
                onPickVehicle(v)
                close()
            } label: {
                HStack(spacing: 12) {
                    RouteTile(short: v.routeShort, colorHex: v.routeColor, textHex: v.routeText)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.vehicleTitle(v)).font(Theme.mono(14)).foregroundStyle(Theme.foreground)
                        Text(v.headsign).font(.system(size: 11.5)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                onToggleWatch(v.id)
            } label: {
                Image(systemName: on ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundStyle(on ? Theme.primary : Theme.mutedForeground)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? "\(Self.vehicleTitle(v)) kiemelésének levétele" : "\(Self.vehicleTitle(v)) kiemelése a térképen")
        }
        .padding(.trailing, 8)
    }
}

/// The county coverage (`core/transit/region.ts`): search lists stops inside
/// it first.
enum MapRegion {
    private static let polygon: [(Double, Double)] = [
        (48.3, 20.08), (48.3, 20.36), (48.47, 20.48), (48.56, 20.75), (48.55, 21.1), (48.52, 21.25), (48.57, 21.45),
        (48.41, 21.7), (48.38, 22.12), (48.25, 21.93), (48.18, 21.7), (48.1, 21.42), (48.0, 21.1), (47.88, 21.09),
        (47.64, 20.88), (47.7, 20.6), (47.7, 20.35), (47.95, 20.47), (48.08, 20.45), (48.12, 20.2), (48.2, 20.06),
    ]

    static func contains(lat: Double, lon: Double) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let (yi, xi) = polygon[i]
            let (yj, xj) = polygon[j]
            if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    static func rank(_ s: Stop) -> Int {
        !TransitIds.isRegional(s.id) || contains(lat: s.lat, lon: s.lon) ? 0 : 1
    }
}
