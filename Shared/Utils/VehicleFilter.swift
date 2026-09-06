//
//  VehicleFilter.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// Turns `FilterState` into the list of vehicles that should be visible.
///
/// Lives outside the views because the map draws it and the fleet list counts
/// it — two surfaces that must never disagree about what "visible" means.
enum VehicleFilter {

    static func apply(
        vehicles: [LiveVehicle],
        filters: FilterState,
        routes: [String: Route],
        position: GeoPosition?
    ) -> [LiveVehicle] {

        let query = filters.vq.trimmingCharacters(in: .whitespaces).normalizedForSearch
        let watchList = filters.watch.map { $0.normalizedForSearch }

        // Looking for one specific bus overrides every other filter: hiding it
        // because it happens to be idle, or off the selected route, would be
        // the wrong answer to the question the rider actually asked.
        if !watchList.isEmpty || !query.isEmpty {
            var targets = watchList
            if !query.isEmpty, !targets.contains(query) { targets.append(query) }
            return vehicles.filter { vehicle in
                let id = vehicle.id.normalizedForSearch
                let label = vehicle.label.normalizedForSearch
                return targets.contains { id.contains($0) || label.contains($0) }
            }
        }

        var list = vehicles

        if filters.type != .all {
            list = list.filter { vehicle in
                let isTram = vehicle.isTram(routes: routes)
                return filters.type == .tram ? isTram : !isTram
            }
        }

        if !filters.routes.isEmpty {
            let routeSet = Set(filters.routes)
            list = list.filter { routeSet.contains($0.routeId) }
        }

        // 0.5 m/s is the noise floor of a parked vehicle's GPS, not motion.
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

    /// Sorted for the fleet list. Route order is the default because that is
    /// how riders name what they are looking for.
    static func sorted(_ vehicles: [LiveVehicle], by sort: VehicleSort) -> [LiveVehicle] {
        switch sort {
        case .id:
            return vehicles.sorted { $0.id < $1.id }
        case .speed:
            return vehicles.sorted { ($0.speed ?? 0) > ($1.speed ?? 0) }
        case .route:
            return vehicles.sorted {
                $0.routeShort == $1.routeShort ? $0.id < $1.id : $0.routeShort < $1.routeShort
            }
        }
    }
}
