//
//  TransitDetail.swift
//  MVK++ (shared)
//

import Foundation

/// One stop of a trip from `/engine/transit/train` or `/engine/transit/trip`.
struct TrainStop: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let platform: String?
    /// The live platform differs from the timetabled one.
    var platformChanged: Bool?
    /// Not announced yet — the platform earlier days used.
    var platformPredicted: Bool?
    let schedArr: String
    let schedDep: String
    let arrUnix: Double
    let depUnix: Double
    let delaySec: Int?
    let passed: Bool
}

struct TransitRouteRef: Decodable, Hashable {
    let key: String
    let short: String
    let long: String
    let color: String
    let text: String
    let mode: TransitMode
    let `operator`: String?
}

struct TransitNotice: Decodable, Hashable {
    let text: String
    let kind: String
}

/// A train by number, or any trip by id, stop by stop.
struct TrainDetailResponse: Decodable {
    let no: String
    let found: Bool
    var tripId: String?
    var date: String?
    var today: Bool?
    var name: String?
    var trainName: String?
    var category: String?
    var route: TransitRouteRef?
    var headsign: String?
    var stops: [TrainStop]?
    var vehicle: LiveVehicle?
    var liveDelaySec: Int?
    var officialDelaySec: Int?
    var notices: [TransitNotice]?
    var cancelled: Bool?
}

/// One direct run from A to B (`/engine/transit/relation`).
struct RelationRow: Decodable, Hashable, Identifiable {
    let tripId: String
    let route: String
    let routeKey: String
    let color: String
    let text: String
    let mode: TransitMode
    let `operator`: String?
    let trainNo: String?
    let trainName: String?
    let headsign: String
    let depStopId: String
    let arrStopId: String
    let depTime: String
    let depUnix: Double
    let schedDepUnix: Double
    let depDelaySec: Int?
    let arrTime: String
    let arrUnix: Double
    let schedArrUnix: Double
    let arrDelaySec: Int?
    let durationMin: Int
    let stops: Int
    let platform: String?
    var platformPredicted: Bool?
    let live: Bool
    let cancelled: Bool
    let vehicle: ArrivalVehicle?
    let notices: [String]?
    let today: Bool

    var id: String { "\(tripId)-\(depUnix)" }
}

struct RelationEnd: Decodable, Hashable {
    let id: String
    let name: String?
}

struct RelationBoardResponse: Decodable {
    let from: RelationEnd
    let to: RelationEnd
    let now: Double
    let rows: [RelationRow]
}

struct TransitSearchStopRoute: Decodable, Hashable {
    let short: String
    let color: String
    let text: String
    let mode: TransitMode
}

struct TransitSearchStop: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    /// `mvk`, `coach` or `rail`.
    let mode: String
    let station: Bool
    let platforms: Int
    let lat: Double
    let lon: Double
    let routes: [TransitSearchStopRoute]
}

struct TransitSearchTrain: Decodable, Hashable, Identifiable {
    let tripId: String
    let no: String
    let name: String
    let headsign: String
    let from: String
    let departure: String
    let today: Bool

    var id: String { tripId }
}

struct TransitSearchResponse: Decodable {
    let q: String
    let stops: [TransitSearchStop]
    let trains: [TransitSearchTrain]
}
