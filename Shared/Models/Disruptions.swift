//
//  Disruptions.swift
//  MVK++ (shared by the Phone and Watch targets)
//

import SwiftUI

/// Mai zavarok (`/engine/disruptions`): today's cancelled, missing and
/// unseen trips.
enum DisruptionKind: String, Decodable, CaseIterable {
    case cancelled, missing, unseen

    var label: String {
        switch self {
        case .cancelled: return "Az MVK törölte"
        case .missing: return "Most kimarad"
        case .unseen: return "Nem láttuk elindulni"
        }
    }

    var short: String {
        switch self {
        case .cancelled: return "Törölve"
        case .missing: return "Kimarad"
        case .unseen: return "Nem indult"
        }
    }

    var hint: String {
        switch self {
        case .cancelled: return "hivatalos MVK-adat"
        case .missing: return "15–90 perce esedékes, egyetlen busz sem vitte"
        case .unseen: return "nincs kihúzva, de nem közlekedett"
        }
    }

    var icon: String {
        switch self {
        case .cancelled: return "nosign"
        case .missing: return "exclamationmark.circle"
        case .unseen: return "eye.slash"
        }
    }

    var tone: Color {
        switch self {
        case .cancelled: return Theme.destructive
        case .missing: return Theme.late
        case .unseen: return Theme.mutedForeground
        }
    }

    var bar: Color {
        switch self {
        case .cancelled: return Theme.destructive
        case .missing: return Theme.late
        case .unseen: return Theme.mutedForeground.opacity(0.6)
        }
    }
}

struct DisruptionTrip: Decodable, Identifiable, Hashable {
    struct Replacement: Decodable, Hashable { let tripId: String; let depTime: String; let gapMin: Int }
    struct Near: Decodable, Hashable { let stopId: String; let name: String; let time: String; let timeS: Int }

    let tripId: String
    var kind: DisruptionKind?
    let routeId: String
    let route: String
    let color: String
    let text: String
    let dir: String
    let headsign: String
    let depS: Int
    let depTime: String
    let arrTime: String
    let from: String
    let to: String
    var replacement: Replacement?
    let near: Near?
    let upcoming: Bool
    var plannedVehicle: String?
    /// Only on the "may start late" list: the bus is still on its previous trip.
    var risk: StartRisk?

    var id: String { tripId }
}

struct StartRisk: Decodable, Hashable {
    let vehicleId: String
    let expectedDelayS: Double
    let level: String
    let prevRoute: String?
    let prevEndUnix: Double
    let predicted: Bool
}

struct Disruptions: Decodable {
    struct Counts: Decodable { let cancelled: Int; let missing: Int; let unseen: Int; let routes: Int }
    struct NearStop: Decodable { let id: String; let name: String }
    struct Hour: Decodable { let h: Int; let cancelled: Int; let missing: Int; let unseen: Int }

    let date: String
    let nowS: Int
    let stale: Bool
    let counts: Counts
    let nearStops: [NearStop]
    let byHour: [Hour]
    let trips: [DisruptionTrip]
    let atRisk: [DisruptionTrip]?

    func count(_ kind: DisruptionKind) -> Int {
        switch kind {
        case .cancelled: return counts.cancelled
        case .missing: return counts.missing
        case .unseen: return counts.unseen
        }
    }
}
