//
//  APIClient+Parking.swift
//  MVK++ Phone App
//

import Foundation

struct ParkingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension APIClient {

    /// `/engine/parking`. The server's own error text wins, as on the web.
    func parking() async throws -> ParkingSnapshot {
        var request = URLRequest(url: try url(path: "/engine/parking"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let reason = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw ParkingError(message: reason ?? "A parkoló most nem érhető el (HTTP \(http.statusCode)).")
        }
        return try decode(data)
    }

    func parkingBlocks() async throws -> ParkingBlocks {
        var request = URLRequest(url: try url(path: "/engine/blocks"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ParkingError(message: "HTTP \(http.statusCode)")
        }
        return try decode(data)
    }
}
