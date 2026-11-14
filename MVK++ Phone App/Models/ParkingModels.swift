//
//  ParkingModels.swift
//  MVK++ Phone App
//

import Foundation

/// The parking snapshot (`/engine/parking`, live on the `parking` WebSocket
/// topic) — the worker's `computeParking` output. Timestamps are unix
/// seconds; a tip's `startS` counts from the service day's `midnight`.
enum ParkingFleetKind: String, Codable, Hashable {
    case bus, tram
}

enum ParkingDepotReason: String, Codable, Hashable {
    case pullIn = "pull-in"
    case seen
    case timeout
    case notToday = "not-today"
}

struct ParkingTripTip: Codable, Hashable {
    let tripId: String
    let route: String
    let startS: Int
    let confidence: Double
    /// MVK has already assigned it (not a guess).
    let certain: Bool
}

struct ParkingFleetHistory: Codable, Hashable {
    let id: String
    let kind: ParkingFleetKind
    let lastDate: String?
    let streakDays: Int
    let outShare: Double?
    let usualOutS: Int?
    /// The last 14 days, oldest first up to yesterday: "1" out, "0" not.
    let recent: String
    let topRoutes: [String]
}

/// A parked vehicle; depot vehicles also carry `reason` and `outToday`, the
/// no-signal list a `place`.
struct ParkingVehicle: Codable, Hashable, Identifiable {
    let id: String
    let kind: ParkingFleetKind
    let since: Double?
    let lastSeen: Double?
    let online: Bool
    let lastRoute: String?
    let lastHeadsign: String?
    let arrivalDelayS: Double?
    let next: ParkingTripTip?
    var reason: ParkingDepotReason?
    var outToday: Bool?
    var place: String?
}

struct ParkingServiceVehicle: Codable, Hashable, Identifiable {
    let id: String
    let kind: ParkingFleetKind
    let route: String?
    let headsign: String?
    let tripId: String?
    let delayS: Double?
    let deadhead: Bool
}

struct ParkingKindCounts: Codable, Hashable {
    var service: Int
    var terminus: Int
    var depot: Int
    var nosignal: Int
    var total: Int
}

struct ParkingTerminalLot: Codable, Hashable, Identifiable {
    let name: String
    let lat: Double
    let lon: Double
    var vehicles: [ParkingVehicle]
    var id: String { name }
}

struct ParkingDepotLot: Codable, Hashable, Identifiable {
    let id: ParkingFleetKind
    let name: String
    var vehicles: [ParkingVehicle]
}

struct ParkingRegional: Codable, Hashable {
    var terminals: [ParkingTerminalLot]
}

struct ParkingSnapshot: Codable, Hashable {
    let at: Double
    let serviceDate: String
    let midnight: Double
    let limitS: Double
    let counts: [String: ParkingKindCounts]
    var terminals: [ParkingTerminalLot]
    var depots: [ParkingDepotLot]
    var nosignal: [ParkingVehicle]
    var service: [ParkingServiceVehicle]
    let fleet: [String: ParkingFleetHistory]
    /// Volán and rail at the county's termini (shown with the Parkoló switch).
    var regional: ParkingRegional?
}

// MARK: - Forda-tábla (`/engine/blocks`)

struct ParkingBlockRun: Codable, Hashable {
    let t: String
    let r: String
    let h: String
    let s: Int
    let e: Int
    let `as`: Int?
    let ae: Int?
    let st: String
    let d: Int?
}

struct ParkingBlockPlan: Codable, Hashable {
    let t: String
    let r: String
    let h: String
    let s: Int
    let e: Int
    let c: Double?
}

struct ParkingBlockRow: Codable, Hashable, Identifiable {
    let id: String
    let kind: ParkingFleetKind
    let runs: [ParkingBlockRun]
    let plan: [ParkingBlockPlan]
}

struct ParkingBlocks: Codable, Hashable {
    let date: String
    let midnight: Double
    /// Seconds of the service day (past 24 h after midnight).
    let now: Int
    let vehicles: [ParkingBlockRow]
}
