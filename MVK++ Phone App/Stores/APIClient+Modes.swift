//
//  APIClient+Modes.swift
//  MVK++ Phone App
//

import Foundation

/// The catalog and live feed for the enabled transport modes, the way the
/// web's `api.getStops(modes)` / `getRoutes(modes)` / `getLivePositions(modes)`
/// ask for them.
extension APIClient {

    func staticCatalog(modes: String) async throws -> (stops: [Stop], routes: [Route], meta: GtfsMeta, routesData: Data, metaData: Data) {
        let query = [URLQueryItem(name: "modes", value: modes)]
        async let stopsTask: [Stop] = request(path: "/gtfs/stops.json", queryItems: query)
        async let routesTask = rawData(path: "/gtfs/routes.json", queryItems: query)
        async let metaTask = rawData(path: "/gtfs/meta.json")

        let (loadedStops, routesData, metaData) = try await (stopsTask, routesTask, metaTask)
        return (
            loadedStops,
            try decode(routesData) as [Route],
            try decode(metaData) as GtfsMeta,
            routesData,
            metaData
        )
    }

    func livePositions(modes: String) async throws -> VehiclePositionsResponse {
        try await request(path: "/live/positions", queryItems: [URLQueryItem(name: "modes", value: modes)])
    }
}
