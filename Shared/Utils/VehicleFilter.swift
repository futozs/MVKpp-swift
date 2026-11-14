//
//  VehicleFilter.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// Turns `FilterState` into the list of vehicles that should be visible — the
/// web's `getVisibleVehicles` and `filter/filterState.ts`. The map draws it,
/// the fleet list counts it, the timeline replays it.
enum VehicleFilter {

    /// The official (MÁV+) delay, otherwise our matcher's measurement.
    static func delay(_ v: LiveVehicle) -> Int? { v.delaySec ?? v.liveDelaySec }

    /// The mode / operator / rail category / delay filters.
    static func matchesModeFilters(_ v: LiveVehicle, _ f: FilterState, routes: [String: Route]) -> Bool {
        let r = routes[v.routeId]
        let mode = v.transitMode(routes: routes)
        if !f.modes.isEmpty, !f.modes.contains(mode) { return false }
        if !f.operators.isEmpty, mode == .coach, !f.operators.contains(r?.operatorName ?? "") { return false }
        if !f.railKinds.isEmpty, mode == .rail, !f.railKinds.contains(r?.short ?? v.routeShort) { return false }
        if f.delay != .all {
            guard let d = delay(v) else { return false }
            if f.delay == .late ? Double(d) < FilterState.lateS : Double(d) >= FilterState.lateS { return false }
        }
        return true
    }

    static func apply(
        vehicles: [LiveVehicle],
        filters: FilterState,
        routes: [String: Route],
        position: GeoPosition?
    ) -> [LiveVehicle] {
        let query = filters.vq.trimmingCharacters(in: .whitespaces).normalizedForSearch
        let watchList = filters.watch.map { $0.normalizedForSearch }

        if !watchList.isEmpty || !query.isEmpty {
            var targets = watchList
            if !query.isEmpty, !targets.contains(query) { targets.append(query) }
            return vehicles.filter { vehicle in
                let keys = [vehicle.id, vehicle.label, vehicle.plate, vehicle.trainNo]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .map(\.normalizedForSearch)
                return targets.contains { t in keys.contains { $0.contains(t) } }
            }
        }

        var list = vehicles.filter { matchesModeFilters($0, filters, routes: routes) }

        if !filters.routes.isEmpty {
            let routeSet = Set(filters.routes)
            list = list.filter { routeSet.contains($0.routeId) }
        }

        switch filters.speed {
        case .moving: list = list.filter { ($0.speed ?? 0) > 0.5 }
        case .idle: list = list.filter { ($0.speed ?? 0) <= 0.5 }
        case .all: break
        }

        if let nearMeKm = filters.nearMeKm, let position {
            list = list.filter { vehicle in
                guard let lat = vehicle.lat, let lon = vehicle.lon else { return false }
                return Geo.distanceKm(position.lat, position.lon, lat, lon) <= nearMeKm
            }
        }

        return list
    }

    static func sorted(_ vehicles: [LiveVehicle], by sort: VehicleSort) -> [LiveVehicle] {
        let hu = Locale(identifier: "hu_HU")
        switch sort {
        case .id:
            return vehicles.sorted { $0.id.compare($1.id, locale: hu) == .orderedAscending }
        case .speed:
            return vehicles.sorted { ($0.speed ?? 0) > ($1.speed ?? 0) }
        case .route:
            return vehicles.sorted {
                let byRoute = $0.routeShort.compare($1.routeShort, locale: hu)
                if byRoute != .orderedSame { return byRoute == .orderedAscending }
                return $0.id.compare($1.id, locale: hu) == .orderedAscending
            }
        }
    }
}
