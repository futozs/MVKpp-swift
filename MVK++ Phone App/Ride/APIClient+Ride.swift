//
//  APIClient+Ride.swift
//  MVK++ Phone App
//

import Foundation

/// How the bus carries on from the trip's terminus (`/engine/continuation`).
struct Continuation: Decodable, Equatable {
    struct Terminus: Decodable, Equatable {
        let stopId: String
        let name: String
        let idx: Int
    }

    struct Next: Decodable, Equatable {
        let tripId: String
        let route: String
        let color: String
        let text: String
        let headsign: String
        let firstStopId: String
        let firstStopName: String
        let depTs: Double
        let depTime: String
        /// `loop`: same stop · `nearby`: the neighbouring bay · nil: elsewhere.
        let kind: String?
        let source: String?
        let cancelled: Bool
        let departed: Bool
        let departedAt: Double?
        let startDelayS: Double?
    }

    struct Point: Decodable, Equatable {
        let lat: Double
        let lon: Double
    }

    let terminus: Terminus?
    let loop: Bool
    let arrivedAt: Double?
    let vehicle: Point?
    let next: Next?
}

/// A route on a calendar day (`/engine/ridelog/routes`).
struct PastRoute: Decodable, Hashable, Identifiable {
    let short: String
    let long: String
    let color: String
    let text: String
    var id: String { short }
}

/// The run of a timetabled trip, if the system saw it.
struct PastRun: Decodable, Hashable {
    let vehicleId: String
    let actualStart: Double?
    let actualEnd: Double?
    let status: String?
}

/// A timetabled trip to pick afterwards (`/engine/ridelog/trips`, `…/next`).
struct PastTripRow: Decodable, Hashable, Identifiable {
    let tripId: String
    let serviceDate: String
    let route: String
    let color: String
    let text: String
    let headsign: String
    let depTs: Double
    let endTs: Double
    let originName: String
    let destinationName: String
    let loopEnd: Bool?
    let run: PastRun?
    /// Only on `…/next`: `loop` or `nearby`.
    let kind: String?
    let sameVehicle: Bool?

    var id: String { "\(serviceDate)|\(tripId)" }
}

/// A congested link right now (`/engine/traffic/live`).
struct LiveTrafficSegment: Decodable, Hashable {
    let fromId: String
    let toId: String
    let excessS: Double
    let level: Double
    var path: [[Double]]?
    var fromName: String?
    var toName: String?
    var normalS: Double?
    var nowS: Double?
    var samples: Int?
    var at: Double?
}

struct LiveTrafficResponse: Decodable {
    let segments: [LiveTrafficSegment]?
}

extension APIClient {
    /// One trip on its service day: stops, measured events, run, delay and forecast.
    func rideTrip(tripId: String, date: String? = nil) async throws -> TripDetailResponse {
        var items = [URLQueryItem(name: "trip", value: tripId)]
        if let date, !date.isEmpty { items.append(URLQueryItem(name: "date", value: date)) }
        return try await request(path: "/engine/trip", queryItems: items)
    }

    func continuation(tripId: String, vehicleId: String) async throws -> Continuation {
        try await request(path: "/engine/continuation", queryItems: [
            URLQueryItem(name: "trip", value: tripId),
            URLQueryItem(name: "vehicle", value: vehicleId),
        ])
    }

    func rideLogRoutes(date: String) async throws -> [PastRoute] {
        struct Body: Decodable { let routes: [PastRoute] }
        let body: Body = try await request(path: "/engine/ridelog/routes", queryItems: [URLQueryItem(name: "date", value: date)])
        return body.routes
    }

    func rideLogTrips(date: String, route: String) async throws -> [PastTripRow] {
        struct Body: Decodable { let trips: [PastTripRow] }
        let body: Body = try await request(path: "/engine/ridelog/trips", queryItems: [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "route", value: route),
        ])
        return body.trips
    }

    func rideLogNext(serviceDate: String, tripId: String, vehicleId: String) async throws -> [PastTripRow] {
        struct Body: Decodable { let choices: [PastTripRow] }
        var items = [URLQueryItem(name: "date", value: serviceDate), URLQueryItem(name: "trip", value: tripId)]
        if !vehicleId.isEmpty { items.append(URLQueryItem(name: "vehicle", value: vehicleId)) }
        let body: Body = try await request(path: "/engine/ridelog/next", queryItems: items)
        return body.choices
    }

    func rideLoopRoutes() async throws -> Set<String> {
        struct Body: Decodable { let routes: [String]? }
        let body: Body = try await request(path: "/engine/ridelog/loops")
        return Set(body.routes ?? [])
    }

    func liveTraffic() async throws -> [LiveTrafficSegment] {
        let body: LiveTrafficResponse = try await request(path: "/engine/traffic/live")
        return body.segments ?? []
    }

    // MARK: - Cloud ride log (`/v3/rides`)

    func uploadRides(_ rides: [Ride], session: String) async throws -> [String] {
        struct Payload: Encodable { let rides: [CloudRide] }
        struct Saved: Decodable { let saved: [String]? }
        var request = URLRequest(url: try url(path: "/v3/rides"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(session, forHTTPHeaderField: "X-Account-Session")
        request.httpBody = try JSONEncoder().encode(Payload(rides: rides.map(CloudRide.init)))
        let (data, response) = try await self.session.data(for: request)
        try Self.check(response)
        let body: Saved = try decode(data)
        return body.saved ?? []
    }

    func downloadRides(session: String) async throws -> [Ride] {
        struct Body: Decodable { let rides: [LossyRide] }
        var request = URLRequest(url: try url(path: "/v3/rides"))
        request.setValue(session, forHTTPHeaderField: "X-Account-Session")
        let (data, response) = try await self.session.data(for: request)
        try Self.check(response)
        let body: Body = try decode(data)
        return body.rides.compactMap(\.ride)
    }

    func deleteRide(id: String, session: String) async throws {
        var request = URLRequest(url: try url(path: "/v3/rides/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue(session, forHTTPHeaderField: "X-Account-Session")
        let (_, response) = try await self.session.data(for: request)
        try Self.check(response)
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
    }
}

/// One malformed entry must not drop the whole log.
struct LossyRide: Decodable {
    let ride: Ride?
    init(from decoder: Decoder) throws {
        ride = try? Ride(from: decoder)
    }
}
