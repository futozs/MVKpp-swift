//
//  APIClient+Board.swift
//  MVK++ (shared by the Phone, Watch and Widget targets)
//

import Foundation

/// Departure boards for the rider's transport modes (web `boardQuery`), plus
/// the engine's news and disruption lists.
extension APIClient {

    /// `tram,bus~all` → `modes=tram,bus&merge=all`.
    static func boardQuery(_ boardKey: String) -> [URLQueryItem] {
        let parts = boardKey.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        var items: [URLQueryItem] = []
        if let modes = parts.first, !modes.isEmpty { items.append(URLQueryItem(name: "modes", value: modes)) }
        if parts.count > 1, !parts[1].isEmpty { items.append(URLQueryItem(name: "merge", value: parts[1])) }
        return items
    }

    func arrivals(stopId: String, limit: Int, boardKey: String) async throws -> StopArrivalsResponse {
        try await request(path: "/live/arrivals", queryItems: [
            URLQueryItem(name: "stop", value: stopId),
            URLQueryItem(name: "limit", value: String(limit)),
        ] + Self.boardQuery(boardKey))
    }

    func multiArrivals(stopIds: [String], limit: Int, boardKey: String) async throws -> MultiArrivalsResponse {
        guard !stopIds.isEmpty else { return MultiArrivalsResponse(results: []) }
        return try await request(path: "/live/multi-arrivals", queryItems: [
            URLQueryItem(name: "stops", value: stopIds.joined(separator: ",")),
            URLQueryItem(name: "limit", value: String(limit)),
        ] + Self.boardQuery(boardKey))
    }

    func news() async throws -> NewsFeed {
        let (data, response) = try await session.data(from: try url(path: "/engine/news"))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return try decode(data)
    }

    /// `near`: stop IDs whose trips come first.
    func disruptions(near: [String] = []) async throws -> Disruptions {
        let items = near.isEmpty ? [] : [URLQueryItem(name: "near", value: near.joined(separator: ","))]
        var request = URLRequest(url: try url(path: "/engine/disruptions", queryItems: items))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return try decode(data)
    }
}
