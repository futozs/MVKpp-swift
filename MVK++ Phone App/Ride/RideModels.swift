//
//  RideModels.swift
//  MVK++ Phone App
//
//  The ride log's records in exactly the web app's localStorage shape
//  (`lib/rides.ts`), so the JSON round-trips to the web, the cloud
//  (`/v3/rides`) and the account sync unchanged. Fields the web types as
//  `T | null` are always written, as `null` when empty.
//

import Foundation

enum RideEndedBy: String, Codable {
    case user, dest, away, terminus
}

enum RideSource: String, Codable {
    case auto, manual, later
}

/// A finished ride (one leg of a journey).
struct Ride: Codable, Identifiable, Equatable {
    var id: String
    var serviceDate: String
    var vehicleId: String
    var tripId: String
    var route: String
    var headsign: String
    var color: String
    var text: String
    var boardedAt: Double
    var alightedAt: Double?
    var fromStopId: String?
    var fromStopName: String?
    var toStopId: String?
    var toStopName: String?
    /// How many stops were ridden.
    var stops: Int?
    /// Stop to stop in straight lines, summed (m).
    var distanceM: Double?
    var delayAtBoardS: Double?
    var delayAtAlightS: Double?
    var detected: RideSource
    /// A loop journey's legs share this id.
    var chainId: String?
    var endedBy: RideEndedBy?
    /// When it was corrected afterwards (unix) — the stops are final from then on.
    var editedAt: Double?
    /// When it was extended or backfilled afterwards (unix).
    var patchedAt: Double?
    /// The trip ends at a turning loop.
    var loopEnd: Bool?
    /// Local only: uploaded to the cloud already.
    var synced: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, serviceDate, vehicleId, tripId, route, headsign, color, text, boardedAt, alightedAt
        case fromStopId, fromStopName, toStopId, toStopName, stops, distanceM, delayAtBoardS, delayAtAlightS
        case detected, chainId, endedBy, editedAt, patchedAt, loopEnd, synced
    }

    init(
        id: String, serviceDate: String, vehicleId: String, tripId: String, route: String, headsign: String,
        color: String, text: String, boardedAt: Double, alightedAt: Double?, fromStopId: String?, fromStopName: String?,
        toStopId: String?, toStopName: String?, stops: Int?, distanceM: Double?, delayAtBoardS: Double?,
        delayAtAlightS: Double?, detected: RideSource, chainId: String? = nil, endedBy: RideEndedBy? = nil,
        editedAt: Double? = nil, patchedAt: Double? = nil, loopEnd: Bool? = nil, synced: Bool? = nil
    ) {
        self.id = id
        self.serviceDate = serviceDate
        self.vehicleId = vehicleId
        self.tripId = tripId
        self.route = route
        self.headsign = headsign
        self.color = color
        self.text = text
        self.boardedAt = boardedAt
        self.alightedAt = alightedAt
        self.fromStopId = fromStopId
        self.fromStopName = fromStopName
        self.toStopId = toStopId
        self.toStopName = toStopName
        self.stops = stops
        self.distanceM = distanceM
        self.delayAtBoardS = delayAtBoardS
        self.delayAtAlightS = delayAtAlightS
        self.detected = detected
        self.chainId = chainId
        self.endedBy = endedBy
        self.editedAt = editedAt
        self.patchedAt = patchedAt
        self.loopEnd = loopEnd
        self.synced = synced
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        serviceDate = try c.decodeIfPresent(String.self, forKey: .serviceDate) ?? ""
        vehicleId = try c.decodeIfPresent(String.self, forKey: .vehicleId) ?? ""
        tripId = try c.decodeIfPresent(String.self, forKey: .tripId) ?? ""
        route = try c.decodeIfPresent(String.self, forKey: .route) ?? ""
        headsign = try c.decodeIfPresent(String.self, forKey: .headsign) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "1FB574"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? "FFFFFF"
        boardedAt = try c.decode(Double.self, forKey: .boardedAt)
        alightedAt = try c.decodeIfPresent(Double.self, forKey: .alightedAt)
        fromStopId = try c.decodeIfPresent(String.self, forKey: .fromStopId)
        fromStopName = try c.decodeIfPresent(String.self, forKey: .fromStopName)
        toStopId = try c.decodeIfPresent(String.self, forKey: .toStopId)
        toStopName = try c.decodeIfPresent(String.self, forKey: .toStopName)
        stops = try c.decodeIfPresent(Int.self, forKey: .stops)
        distanceM = try c.decodeIfPresent(Double.self, forKey: .distanceM)
        delayAtBoardS = try c.decodeIfPresent(Double.self, forKey: .delayAtBoardS)
        delayAtAlightS = try c.decodeIfPresent(Double.self, forKey: .delayAtAlightS)
        detected = (try? c.decodeIfPresent(RideSource.self, forKey: .detected)) ?? .manual
        chainId = try c.decodeIfPresent(String.self, forKey: .chainId)
        endedBy = try? c.decodeIfPresent(RideEndedBy.self, forKey: .endedBy)
        editedAt = try c.decodeIfPresent(Double.self, forKey: .editedAt)
        patchedAt = try c.decodeIfPresent(Double.self, forKey: .patchedAt)
        loopEnd = try c.decodeIfPresent(Bool.self, forKey: .loopEnd)
        synced = try c.decodeIfPresent(Bool.self, forKey: .synced)
    }

    func encode(to encoder: Encoder) throws {
        try encode(to: encoder, includeLocal: true)
    }

    /// `includeLocal: false` drops the device-only `synced` flag (the cloud payload).
    func encode(to encoder: Encoder, includeLocal: Bool) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(serviceDate, forKey: .serviceDate)
        try c.encode(vehicleId, forKey: .vehicleId)
        try c.encode(tripId, forKey: .tripId)
        try c.encode(route, forKey: .route)
        try c.encode(headsign, forKey: .headsign)
        try c.encode(color, forKey: .color)
        try c.encode(text, forKey: .text)
        try c.encode(boardedAt, forKey: .boardedAt)
        try c.encode(alightedAt, forKey: .alightedAt)
        try c.encode(fromStopId, forKey: .fromStopId)
        try c.encode(fromStopName, forKey: .fromStopName)
        try c.encode(toStopId, forKey: .toStopId)
        try c.encode(toStopName, forKey: .toStopName)
        try c.encode(stops, forKey: .stops)
        try c.encode(distanceM, forKey: .distanceM)
        try c.encode(delayAtBoardS, forKey: .delayAtBoardS)
        try c.encode(delayAtAlightS, forKey: .delayAtAlightS)
        try c.encode(detected, forKey: .detected)
        try c.encode(chainId, forKey: .chainId)
        try c.encodeIfPresent(endedBy, forKey: .endedBy)
        try c.encodeIfPresent(editedAt, forKey: .editedAt)
        try c.encodeIfPresent(patchedAt, forKey: .patchedAt)
        try c.encodeIfPresent(loopEnd, forKey: .loopEnd)
        if includeLocal { try c.encodeIfPresent(synced, forKey: .synced) }
    }
}

/// The cloud payload of a ride: everything but the local `synced` flag.
struct CloudRide: Encodable {
    let ride: Ride
    func encode(to encoder: Encoder) throws { try ride.encode(to: encoder, includeLocal: false) }
}

/// Loop journey at the terminus: the trip ended and, as the rider said up
/// front, the ride carries on with the bus's next trip once it leaves.
struct RideTurn: Codable, Equatable {
    /// When the bus reached the terminus (unix).
    var arrivedAt: Double
    /// The terminus's index among the finished trip's stops.
    var atIdx: Int
    var terminusName: String
}

/// Loop journey planned ahead: stays on at the terminus and gets off at a
/// stop of the next trip (nil: chosen after the next trip leaves).
struct LoopPlan: Codable, Equatable {
    var stopId: String?
    var stopName: String?
    var tripId: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stopId, forKey: .stopId)
        try c.encode(stopName, forKey: .stopName)
        try c.encode(tripId, forKey: .tripId)
    }
}

struct RidePoint: Codable, Equatable {
    var lat: Double
    var lon: Double
}

struct WithBus: Codable, Equatable {
    var passed: Int
    var at: Double
}

/// The ride in progress.
struct ActiveRide: Codable, Equatable, Identifiable {
    var id: String
    var serviceDate: String
    var vehicleId: String
    var tripId: String
    var route: String
    var headsign: String
    var color: String
    var text: String
    var boardedAt: Double
    /// Legacy: where the detector noticed the ride.
    var boardNear: RidePoint?
    var fromIdx: Int?
    /// The rider picked the boarding stop themselves.
    var fromConfirmed: Bool?
    /// When the phone was last with the bus: the stop it had passed and when.
    var withBus: WithBus?
    var fromStopId: String?
    var fromStopName: String?
    var delayAtBoardS: Double?
    /// Where the rider gets off (index among the trip's stops).
    var destIdx: Int?
    /// Loop journey's next leg: the alighting stop until its stops load.
    var destStopId: String?
    var destStopName: String?
    var loopPlan: LoopPlan?
    var detected: RideSource
    var chainId: String?
    /// Which leg of a loop journey (from 1).
    var leg: Int?
    var turn: RideTurn?

    private enum CodingKeys: String, CodingKey {
        case id, serviceDate, vehicleId, tripId, route, headsign, color, text, boardedAt, boardNear, fromIdx
        case fromConfirmed, withBus, fromStopId, fromStopName, delayAtBoardS, destIdx, destStopId, destStopName
        case loopPlan, detected, chainId, leg, turn
    }

    init(
        id: String, serviceDate: String, vehicleId: String, tripId: String, route: String, headsign: String,
        color: String, text: String, boardedAt: Double, boardNear: RidePoint? = nil, fromIdx: Int?,
        fromConfirmed: Bool? = nil, withBus: WithBus? = nil, fromStopId: String?, fromStopName: String?,
        delayAtBoardS: Double?, destIdx: Int?, destStopId: String? = nil, destStopName: String? = nil,
        loopPlan: LoopPlan? = nil, detected: RideSource, chainId: String? = nil, leg: Int? = nil, turn: RideTurn? = nil
    ) {
        self.id = id
        self.serviceDate = serviceDate
        self.vehicleId = vehicleId
        self.tripId = tripId
        self.route = route
        self.headsign = headsign
        self.color = color
        self.text = text
        self.boardedAt = boardedAt
        self.boardNear = boardNear
        self.fromIdx = fromIdx
        self.fromConfirmed = fromConfirmed
        self.withBus = withBus
        self.fromStopId = fromStopId
        self.fromStopName = fromStopName
        self.delayAtBoardS = delayAtBoardS
        self.destIdx = destIdx
        self.destStopId = destStopId
        self.destStopName = destStopName
        self.loopPlan = loopPlan
        self.detected = detected
        self.chainId = chainId
        self.leg = leg
        self.turn = turn
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(serviceDate, forKey: .serviceDate)
        try c.encode(vehicleId, forKey: .vehicleId)
        try c.encode(tripId, forKey: .tripId)
        try c.encode(route, forKey: .route)
        try c.encode(headsign, forKey: .headsign)
        try c.encode(color, forKey: .color)
        try c.encode(text, forKey: .text)
        try c.encode(boardedAt, forKey: .boardedAt)
        try c.encodeIfPresent(boardNear, forKey: .boardNear)
        try c.encode(fromIdx, forKey: .fromIdx)
        try c.encodeIfPresent(fromConfirmed, forKey: .fromConfirmed)
        try c.encodeIfPresent(withBus, forKey: .withBus)
        try c.encode(fromStopId, forKey: .fromStopId)
        try c.encode(fromStopName, forKey: .fromStopName)
        try c.encode(delayAtBoardS, forKey: .delayAtBoardS)
        try c.encode(destIdx, forKey: .destIdx)
        try c.encodeIfPresent(destStopId, forKey: .destStopId)
        try c.encodeIfPresent(destStopName, forKey: .destStopName)
        try c.encodeIfPresent(loopPlan, forKey: .loopPlan)
        try c.encode(detected, forKey: .detected)
        try c.encodeIfPresent(chainId, forKey: .chainId)
        try c.encodeIfPresent(leg, forKey: .leg)
        try c.encodeIfPresent(turn, forKey: .turn)
    }
}

/// What starts a ride: the vehicle and trip the rider got on.
struct BoardInfo: Equatable {
    let tripId: String
    let vehicleId: String
    let route: String
    let color: String
    let text: String
    let headsign: String
}

/// Where the phone stood next to the bus before they set off together
/// (device time, unix s).
struct BoardingSpot: Equatable {
    let at: Double
    let lat: Double
    let lon: Double
}

/// A loop journey's next leg.
struct NextLeg {
    let tripId: String
    let route: String
    let headsign: String
    let color: String
    let text: String
    let boardedAt: Double
    let fromStopId: String?
    let fromStopName: String?
    let delayAtBoardS: Double?
}

/// How a ride ends.
struct RideEnd {
    var alightedAt: Double?
    var toStopId: String?
    var toStopName: String?
    var stops: Int?
    var distanceM: Double?
    var delayAtAlightS: Double?
    var boardedAt: Double?
    /// `.some(nil)` writes an explicit null; `nil` leaves it untouched.
    var delayAtBoardS: Double??
    var loopEnd: Bool?
    var endedBy: RideEndedBy?
}

/// An afterwards correction of where the rider got on and off.
struct RideFix {
    var fromStopId: String??
    var fromStopName: String??
    var toStopId: String??
    var toStopName: String??
    var boardedAt: Double?
    var alightedAt: Double??
    var stops: Int??
    var distanceM: Double??
    var delayAtBoardS: Double??
    var delayAtAlightS: Double??

    func apply(to r: inout Ride) {
        if let v = fromStopId { r.fromStopId = v }
        if let v = fromStopName { r.fromStopName = v }
        if let v = toStopId { r.toStopId = v }
        if let v = toStopName { r.toStopName = v }
        if let v = boardedAt { r.boardedAt = v }
        if let v = alightedAt { r.alightedAt = v }
        if let v = stops { r.stops = v }
        if let v = distanceM { r.distanceM = v }
        if let v = delayAtBoardS { r.delayAtBoardS = v }
        if let v = delayAtAlightS { r.delayAtAlightS = v }
    }
}
