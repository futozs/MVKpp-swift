//
//  APIClient.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case badStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Érvénytelen URL"
        case .badStatus(let code): return "Szerverhiba (\(code))"
        case .decoding: return "Hibás válaszformátum"
        }
    }
}

/// Talks directly to the self-hosted MVK gateway (see `APIConfig`). The
/// read-only GTFS and live endpoints need no auth; the gateway injects the
/// upstream Bearer token itself on the `/api/*` proxy routes.
struct APIClient {
    static let shared = APIClient()

    let session: URLSession
    let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Transport

    func url(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func request<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let (data, response) = try await session.data(from: try url(path: path, queryItems: queryItems))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return try decode(data)
    }

    /// The gateway's bytes, undecoded. The offline pack stores responses
    /// verbatim so the screens that read them back can use the very same
    /// `Decodable` types, with no second serialization format to keep in step.
    func rawData(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let (data, response) = try await session.data(from: try url(path: path, queryItems: queryItems))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return data
    }

    func post<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        var request = URLRequest(url: try url(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return try decode(data)
    }

    // MARK: - GTFS static

    func stops() async throws -> [Stop] {
        try await request(path: "/gtfs/stops.json")
    }

    func routes() async throws -> [Route] {
        try await request(path: "/gtfs/routes.json")
    }

    func gtfsMeta() async throws -> GtfsMeta {
        try await request(path: "/gtfs/meta.json")
    }

    /// Stops, routes and metadata in one pass, with the routes and metadata
    /// bytes handed back so they can be mirrored into the App Group verbatim.
    /// A cold launch with no signal reads that mirror instead.
    func staticCatalog() async throws -> (stops: [Stop], routes: [Route], meta: GtfsMeta, routesData: Data, metaData: Data) {
        async let stopsTask = stops()
        async let routesTask = rawData(path: "/gtfs/routes.json")
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

    /// Drawable shapes for the given routes. Returns empty rather than calling
    /// the gateway with an empty `route=` parameter.
    func routeGeo(routeIds: [String]) async throws -> RouteGeoResponse {
        guard !routeIds.isEmpty else { return RouteGeoResponse(routes: []) }
        return try await request(path: "/gtfs/route-geo", queryItems: [
            URLQueryItem(name: "route", value: routeIds.joined(separator: ",")),
        ])
    }

    // MARK: - Timetable

    func timetableRoutes(date: String? = nil) async throws -> TimetableRoutesResponse {
        try await request(path: "/gtfs/timetable/routes", queryItems: dateQuery(date))
    }

    func timetable(routeId: String, dir: String, date: String? = nil) async throws -> TimetableResponse {
        var items = [
            URLQueryItem(name: "route", value: routeId),
            URLQueryItem(name: "dir", value: dir),
        ]
        items.append(contentsOf: dateQuery(date))
        return try await request(path: "/gtfs/timetable", queryItems: items)
    }

    func tripJournal(date: String? = nil) async throws -> TripJournalResponse {
        try await request(path: "/gtfs/trip-journal", queryItems: dateQuery(date))
    }

    // MARK: - Timetable, undecoded
    //
    // What the offline downloader pulls. It needs the bytes to file away, and
    // the decoded value to build the per-stop index from, so both come out of
    // one round trip.

    func timetableRoutesData(date: String? = nil) async throws -> Data {
        try await rawData(path: "/gtfs/timetable/routes", queryItems: dateQuery(date))
    }

    func timetableData(routeId: String, dir: String, date: String? = nil) async throws -> Data {
        var items = [
            URLQueryItem(name: "route", value: routeId),
            URLQueryItem(name: "dir", value: dir),
        ]
        items.append(contentsOf: dateQuery(date))
        return try await rawData(path: "/gtfs/timetable", queryItems: items)
    }

    // MARK: - Live

    func livePositions() async throws -> VehiclePositionsResponse {
        try await request(path: "/live/positions")
    }

    func arrivals(stopId: String, limit: Int = 8) async throws -> StopArrivalsResponse {
        try await request(path: "/live/arrivals", queryItems: [
            URLQueryItem(name: "stop", value: stopId),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    func multiArrivals(stopIds: [String], limit: Int = 3) async throws -> MultiArrivalsResponse {
        guard !stopIds.isEmpty else { return MultiArrivalsResponse(results: []) }
        return try await request(path: "/live/multi-arrivals", queryItems: [
            URLQueryItem(name: "stops", value: stopIds.joined(separator: ",")),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    func tripProgress(tripId: String, vehicleId: String? = nil) async throws -> TripProgressResponse {
        try await request(path: "/live/trip-progress", queryItems: tripQuery(tripId, vehicleId))
    }

    func tripPath(tripId: String, vehicleId: String? = nil) async throws -> TripPathResponse {
        try await request(path: "/live/trip-path", queryItems: tripQuery(tripId, vehicleId))
    }

    func cancelledTrips(date: String? = nil) async throws -> CancelledTripsResponse {
        try await request(path: "/live/cancelled", queryItems: dateQuery(date))
    }

    // MARK: - Ancillary

    func weather() async throws -> WeatherResponse {
        try await request(path: "/weather")
    }

    /// MVK's own multi-modal planner, proxied through the gateway.
    func planRoute(from: RoutePlanPoint, to: RoutePlanPoint, departureTime: String) async throws -> RoutePlanResponse {
        try await post(
            path: "/api/v1/route/plan",
            body: RoutePlanRequest(points: [from, to], departureTime: departureTime)
        )
    }

    // MARK: - Measured history
    //
    // These live behind `/stats`, a separate warehouse service. It answers 503
    // when it is down, which is a different situation from an error — the rest
    // of the app keeps working, there are simply no measurements.

    /// Measured travel time between two stops around a moment in time.
    func segmentEstimate(from: String, to: String, at: String) async throws -> SegmentEstimate {
        try await statsRequest(path: "/stats/segment", queryItems: [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "at", value: at),
        ])
    }

    /// Average lateness for each (route, boarding stop) pair, in one call —
    /// an itinerary can have several legs and they must not become several
    /// round trips.
    func routeDelays(at: String, legs: [RouteDelayLeg]) async throws -> RouteDelaysResponse {
        guard !legs.isEmpty else { return RouteDelaysResponse(results: []) }
        var request = URLRequest(url: try url(path: "/stats/route-delays"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RouteDelaysRequest(at: at, legs: legs))

        let (data, response) = try await session.data(for: request)
        try checkStats(response: response, data: data)
        return try decode(data)
    }

    func statsRequest<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        let (data, response) = try await session.data(from: try url(path: path, queryItems: queryItems))
        try checkStats(response: response, data: data)
        return try decode(data)
    }

    func checkStats(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 503 {
            let reason = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw StatsUnavailableError(reason: reason ?? "Az adatraktár nem érhető el.")
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
    }

    // MARK: - Query helpers

    private func dateQuery(_ date: String?) -> [URLQueryItem] {
        guard let date, !date.isEmpty else { return [] }
        return [URLQueryItem(name: "date", value: date)]
    }

    private func tripQuery(_ tripId: String, _ vehicleId: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "trip", value: tripId)]
        if let vehicleId, !vehicleId.isEmpty {
            items.append(URLQueryItem(name: "vehicle", value: vehicleId))
        }
        return items
    }
}
