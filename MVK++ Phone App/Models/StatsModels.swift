//
//  StatsModels.swift
//  MVK++ Phone App
//

import Foundation

// The warehouse's JSON, as the web's `services/statsApi.ts` types it.

struct StatsHealthCounts: Decodable {
    let pings: Int
    let runs: Int
    let events: Int
    let segments: Int
    let profiles: Int
    let vehicles: Int
}

struct StatsFeedHealth: Decodable {
    let service_date: String
    let polls_ok: Int
    let polls_fail: Int
    let pings_kept: Int
    let pings_dup: Int
    let vehicles_max: Int
}

struct StatsJobRow: Decodable {
    let job: String
    let started_at: String
    let ended_at: String?
    let ok: Int
    let rows_out: Int
    let note: String?
}

struct StatsHealth: Decodable {
    let today: StatsFeedHealth?
    let counts: StatsHealthCounts
    let jobs: [StatsJobRow]
}

struct StatsVehicleListItem: Decodable {
    let vehicle_id: String
    let kind: String
    let last_seen: String
    let runs: Int
    let days: Int
    let last_date: String?
    let dist_km: Double
}

struct StatsVehicleList: Decodable {
    let vehicles: [StatsVehicleListItem]
}

struct StatsVehicleDay: Decodable {
    let runs: Int
    let routes_n: Int
    let dist_m: Double
    let service_s: Double
    let moving_s: Double?
    let dwell_s: Double
    let max_speed_dms: Double?
    let avg_delay_s: Double?
    let p85_delay_s: Double?
    let first_ts: Double?
    let last_ts: Double?
    let gaps_n: Int
}

struct StatsVehicleRun: Decodable, Identifiable {
    let run_id: Int
    let sched_start_s: Int
    let sched_end_s: Int
    let actual_start: Double?
    let actual_end: Double?
    let start_delay_s: Double?
    let end_delay_s: Double?
    let dist_m: Double?
    let stops_seen: Int
    let stops_total: Int
    let quality: Int
    let status: String
    let route_short: String
    let color: String?
    let headsign: String?
    let direction: Int

    var id: Int { run_id }
}

struct StatsVehicleDetail: Decodable {
    let vehicleId: String
    let date: String
    let summary: StatsVehicleDay?
    let runs: [StatsVehicleRun]
    let days: [String]?
}

/// `[unix, lat, lon, speed (dm/s) | null, flag | null]`
struct StatsTrackPoint: Decodable {
    let t: Double
    let lat: Double
    let lon: Double
    let speed: Double?

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        t = try c.decode(Double.self)
        lat = try c.decode(Double.self)
        lon = try c.decode(Double.self)
        speed = c.isAtEnd ? nil : try c.decodeIfPresent(Double.self)
    }
}

struct StatsVehicleTrack: Decodable {
    let vehicleId: String
    let date: String
    let points: Int
    let ofTotal: Int
    let track: [StatsTrackPoint]
}

struct StatsVehicleRouteShare: Decodable {
    let period_ym: Int
    let route_short: String
    let color: String?
    let kind: String
    let runs: Int
    let share_pct: Double
    let dist_km: Double
    let service_s: Double
    let days_active: Int
    let avg_delay_s: Double?
}

struct StatsVehicleRoutes: Decodable {
    let vehicleId: String
    let routes: [StatsVehicleRouteShare]
}

struct StatsIncident: Decodable, Identifiable {
    let incident_id: Int
    let kind: String
    let service_date: String
    let started_ts: Double
    let ended_ts: Double?
    let duration_s: Double?
    let confidence: Int
    let absent_days: Int?
    let note: String?
    let vehicle_id: String

    var id: Int { incident_id }
}

struct StatsVehicleIncidents: Decodable {
    let vehicleId: String
    let incidents: [StatsIncident]
}

struct StatsRouteDay: Decodable {
    let service_date: String
    let direction: Int
    let runs: Int
    let ghost_runs: Int
    let events_n: Int
    let otp_pct: Double?
    let avg_delay_s: Double?
    let p85_delay_s: Double?
    let bunching_n: Int
}

struct StatsRouteResponse: Decodable {
    let route: String
    let days: [StatsRouteDay]
}

struct StatsStopHour: Decodable {
    let service_date: String
    let hour: Int
    let events_n: Int
    let otp_pct: Double?
    let avg_delay_s: Double?
    let p85_delay_s: Double?
    let avg_dwell_s: Double?
    let avg_headway_s: Double?
}

struct StatsStopResponse: Decodable {
    let stop: String
    let name: String?
    let hours: [StatsStopHour]
}

struct StatsNetworkHour: Decodable {
    let hour: Int
    let days: Int
    let n: Int
    let avg_delay_s: Double?
    let otp_pct: Double?
    let late_pct: Double?
    let p85_delay_s: Double?
}

struct StatsNetworkSlow: Decodable {
    let from_stop: String
    let to_stop: String
    let from_name: String
    let to_name: String
    let n: Int
    let p50_s: Double
    let p85_s: Double
    let sched_s: Double
    let excess_s: Double
    let excess_pct: Double?
}

struct StatsNetworkProfile: Decodable {
    let daytype: Int
    let days: Int
    let fromHour: Int
    let toHour: Int
    let hourly: [StatsNetworkHour]
    let slow: [StatsNetworkSlow]
}

struct StatsIncidentV3: Decodable, Identifiable {
    let id: Int
    let service_date: String
    let kind: String
    let source: String
    let confidence: Int
    let route_short: String?
    let color: String?
    let text_color: String?
    let vehicle_id: String?
    let started_ts: Double
    let title: String
    let detail: String?
}

struct StatsIncidentDay: Decodable {
    let service_date: String
    let kind: String
    let n: Int
}

struct StatsIncidentsV3: Decodable {
    let from: String
    let to: String
    let incidents: [StatsIncidentV3]
    let byDay: [StatsIncidentDay]
}

/// `/engine/incidents/live`
struct StatsLiveMissing: Decodable, Identifiable {
    let tripId: String
    let route: String
    let time: String
    let headsign: String
    let lateMin: Int

    var id: String { tripId }
}

struct StatsLiveIncidents: Decodable {
    let date: String
    let cancelled: Int
    let missing: [StatsLiveMissing]
}

// MARK: - Plate prediction

struct StatsHitCount: Decodable {
    let n: Int
    let hits: Int
}

struct StatsPredictionGuess: Decodable, Hashable {
    let h: Int
    let v: String
    let ok: Bool
    let c: Double
    let m: String
}

struct StatsPredictionTrip: Decodable, Identifiable {
    let date: String
    let trip_id: String
    let route_short: String
    let color: String?
    let text_color: String?
    let sched_start_s: Int
    let actual: String
    let headsign: String?
    let guesses: [StatsPredictionGuess]

    var id: String { "\(date)|\(trip_id)" }
}

struct StatsPredictionData: Decodable {
    struct Horizon: Decodable { let horizon: Int; let n: Int; let hits: Int; let avg_conf: Double }
    struct Calibration: Decodable { let bucket: Int; let n: Int; let hits: Int; let avg_conf: Double }
    struct Method: Decodable { let method: String; let n: Int; let hits: Int; let avg_conf: Double }
    struct Signal: Decodable { let signal: String; let n: Int; let hits: Int }
    struct Weight: Decodable { let signal: String; let weight: Double; let hits: Int; let misses: Int }
    struct Daily: Decodable { let date: String; let n: Int; let hits: Int }
    struct Hour: Decodable { let hour: Int; let n: Int; let hits: Int }
    struct RouteRow: Decodable { let route_short: String; let color: String?; let text_color: String?; let n: Int; let hits: Int }
    struct VehicleRow: Decodable { let vehicle_id: String; let n: Int; let hits: Int; let wrong_picks: Int }

    let from: String
    let to: String
    let pendingToday: Int
    let byHorizon: [Horizon]
    let calibration: [Calibration]
    let byMethod: [Method]
    let signals: [Signal]
    let weights: [Weight]
    let daily: [Daily]
    let byHour: [Hour]
    let byRoute: [RouteRow]
    let byVehicle: [VehicleRow]
    let trips: [StatsPredictionTrip]
}

// MARK: - Forecast model

struct StatsForecastBucket: Decodable {
    let n: Int
    let maeBaseline: Double
    let maeModel: Double
    let coverBaseline: Double
    let coverModel: Double
    let useMedian: Bool
}

struct StatsForecastReport: Decodable {
    struct Rows: Decodable { let train: Int; let test: Int }
    struct Days: Decodable { let train: [String]; let test: [String] }
    struct Cell: Decodable { let useMedian: Bool }
    struct Overall: Decodable { let maeBaseline: Double; let maeModel: Double; let improvement: Double }

    let rows: Rows
    let days: Days
    let buckets: [String: StatsForecastBucket]
    let cells: [String: Cell]?
    let overall: Overall
}

struct StatsForecastStatus: Decodable {
    struct InUse: Decodable { let trainedAt: String?; let report: StatsForecastReport? }
    struct Training: Decodable { let trainedAt: String; let accepted: Bool; let report: StatsForecastReport }

    let inUse: InUse
    let lastTraining: Training?
}

// MARK: - Regional

struct StatsRegional: Decodable {
    struct Summary: Decodable {
        let n: Int?
        let ontime: Double?
        let late: Double?
        let avg_delay_s: Double?
        let p85_delay_s: Double?
    }
    struct Train: Decodable {
        let name: String
        let route_short: String
        let short_name: String?
        let color: String?
        let text_color: String?
        let kind: String?
        let runs: Int
        let avg_end_delay_s: Double?
        let p85_end_delay_s: Double?
        let ontime_pct: Double?
    }
    struct Cause: Decodable { let text: String; let kind: String; let n: Int }
    struct Platforms: Decodable { let n: Int; let changed: Int }
    struct Daily: Decodable { let date: String; let n: Int; let ontime: Double?; let avg_delay_s: Double? }

    let days: Int
    let feeds: [String]
    let summary: Summary?
    let trains: [Train]
    let causes: [Cause]
    let platforms: Platforms?
    let daily: [Daily]
}

// MARK: - Heat

struct StatsRouteHeat: Decodable {
    struct Direction: Decodable { let dir: String; let headsign: String; let trips: Int }
    struct HeatStop: Decodable { let id: String; let name: String }
    struct Hours: Decodable { let from: Int; let to: Int }
    /// `[stop index, hour, samples, median delay, 85% delay, median delay gain | null]`
    struct Cell: Decodable {
        let stop: Int
        let h: Int
        let n: Int
        let p50: Double
        let p85: Double
        let gain: Double?

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            stop = Int(try c.decode(Double.self))
            h = Int(try c.decode(Double.self))
            n = Int(try c.decode(Double.self))
            p50 = try c.decode(Double.self)
            p85 = try c.decode(Double.self)
            gain = c.isAtEnd ? nil : try c.decodeIfPresent(Double.self)
        }
    }

    let route: String
    let dir: String
    let days: Int
    let daytype: Int
    let directions: [Direction]
    let stops: [HeatStop]
    let hours: Hours
    let cells: [Cell]
}

struct StatsCityHeat: Decodable {
    struct Segment: Decodable, Identifiable {
        let from: String
        let to: String
        let routes: [String]
        let m: Double
        let path: [[Double]]
        let ex: [Double?]
        let n: [Int]
        let sched: [Double?]

        var id: String { "\(from)→\(to)|\(routes.joined(separator: ","))|\(path.first?.first ?? 0)" }
    }

    let days: Int
    let daytype: Int
    let hours: StatsRouteHeat.Hours
    let segments: [Segment]
}
