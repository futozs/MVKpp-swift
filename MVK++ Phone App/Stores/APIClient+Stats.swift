//
//  APIClient+Stats.swift
//  MVK++ Phone App
//

import Foundation

/// A failed `/engine/*` request, with the web's wording for the status.
struct StatsEngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The Statistika tab's endpoints (web `services/statsApi.ts`).
///
/// `/stats/*` is the warehouse (503 = unavailable); the `/v3/...` root
/// endpoints mirror the web's `getRoot`, where a 503 also means unavailable.
extension APIClient {

    // MARK: - Warehouse (`get`)

    func statsHealth() async throws -> StatsHealth {
        try await warehouse(path: "/health", queryItems: [])
    }

    func statsVehicles(modes: String?) async throws -> StatsVehicleList {
        try await warehouse(path: "/vehicles", queryItems: modes.map { [URLQueryItem(name: "modes", value: $0)] } ?? [])
    }

    func statsVehicle(id: String, date: String) async throws -> StatsVehicleDetail {
        try await warehouse(path: "/vehicle/\(id)", queryItems: [URLQueryItem(name: "date", value: date)])
    }

    func statsVehicleTrack(id: String, date: String, every: Int = 2) async throws -> StatsVehicleTrack {
        try await warehouse(path: "/vehicle/\(id)/track", queryItems: [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "every", value: String(every)),
        ])
    }

    func statsVehicleRoutes(id: String) async throws -> StatsVehicleRoutes {
        try await warehouse(path: "/vehicle/\(id)/routes", queryItems: [])
    }

    func statsVehicleIncidents(id: String) async throws -> StatsVehicleIncidents {
        try await warehouse(path: "/vehicle/\(id)/incidents", queryItems: [])
    }

    func statsRoute(short: String, from: String, to: String) async throws -> StatsRouteResponse {
        try await warehouse(path: "/route/\(short)", queryItems: [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ])
    }

    func statsStop(id: String, from: String, to: String) async throws -> StatsStopResponse {
        try await warehouse(path: "/stop/\(id)", queryItems: [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ])
    }

    /// The web's `get`: a failure reads `Statisztika [404] /vehicle/123?date=…: body`.
    private func warehouse<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        let (data, response) = try await session.data(from: try url(path: "/stats\(path)", queryItems: queryItems))
        if let http = response as? HTTPURLResponse, http.statusCode != 503, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            let text = body.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : body
            throw StatsEngineError(message: "Statisztika [\(http.statusCode)] \(Self.shown(path, queryItems)): \(text)")
        }
        try checkStats(response: response, data: data)
        return try decode(data)
    }

    private static func shown(_ path: String, _ queryItems: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
    }

    // MARK: - v3 (`getRoot`)

    func statsRegional(days: Int, modes: String) async throws -> StatsRegional {
        var items = [URLQueryItem(name: "days", value: String(days))]
        if !modes.isEmpty { items.append(URLQueryItem(name: "modes", value: modes)) }
        return try await statsRoot(path: "/v3/stats/regional", queryItems: items)
    }

    func statsNetwork(daytype: Int, days: Int, fromHour: Int, toHour: Int) async throws -> StatsNetworkProfile {
        try await statsRoot(path: "/v3/stats/network", queryItems: [
            URLQueryItem(name: "daytype", value: String(daytype)),
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "fromHour", value: String(fromHour)),
            URLQueryItem(name: "toHour", value: String(toHour)),
        ])
    }

    func statsIncidentsV3(from: String, to: String, kind: String?, minConfidence: Int = 50) async throws -> StatsIncidentsV3 {
        var items = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "minConfidence", value: String(minConfidence)),
        ]
        if let kind { items.append(URLQueryItem(name: "kind", value: kind)) }
        return try await statsRoot(path: "/v3/incidents", queryItems: items)
    }

    func statsPredictions(from: String, to: String) async throws -> StatsPredictionData {
        try await statsRoot(path: "/v3/stats/predictions", queryItems: [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ])
    }

    private func statsRoot<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        let (data, response) = try await session.data(from: try url(path: path, queryItems: queryItems))
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 503 { throw StatsUnavailableError(reason: "Az adatraktár nem érhető el.") }
            if !(200..<300).contains(http.statusCode) {
                throw StatsEngineError(message: "Statisztika [\(http.statusCode)] \(Self.shown(path, queryItems))")
            }
        }
        return try decode(data)
    }

    // MARK: - Engine

    func liveIncidents() async throws -> StatsLiveIncidents {
        try await request(path: "/engine/incidents/live")
    }

    func forecastModelStatus() async throws -> StatsForecastStatus {
        let (data, response) = try await session.data(from: try url(path: "/engine/ml/status"))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StatsEngineError(message: "Hiba (\(http.statusCode))")
        }
        return try decode(data)
    }

    func routeHeat(route: String, dir: String?, days: Int, daytype: Int) async throws -> StatsRouteHeat {
        var items = [URLQueryItem(name: "route", value: route)]
        if let dir { items.append(URLQueryItem(name: "dir", value: dir)) }
        items.append(URLQueryItem(name: "days", value: String(days)))
        items.append(URLQueryItem(name: "daytype", value: String(daytype)))
        return try await heatRequest(path: "/engine/heat/route", queryItems: items)
    }

    func cityHeat(days: Int, daytype: Int) async throws -> StatsCityHeat {
        try await heatRequest(path: "/engine/heat/city", queryItems: [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "daytype", value: String(daytype)),
        ])
    }

    private func heatRequest<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        let (data, response) = try await session.data(from: try url(path: path, queryItems: queryItems))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 404: throw StatsEngineError(message: "Erre a vonalra nincs adat.")
            case 503: throw StatsEngineError(message: "A menetrend még töltődik próbáld újra pár másodperc múlva.")
            default: throw StatsEngineError(message: "Hiba (\(http.statusCode))")
            }
        }
        return try decode(data)
    }
}
