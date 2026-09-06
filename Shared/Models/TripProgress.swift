//
//  TripProgress.swift
//  MVK++ Watch App
//

import Foundation

struct TripProgressStop: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let lat: Double?
    let lon: Double?
    let dep: Int
}

struct TripProgressVehicle: Decodable, Hashable {
    let id: String
    let lat: Double
    let lon: Double
    let speed: Double?
}

struct TripProgressResponse: Decodable {
    let tripId: String
    let live: Bool
    let vehicle: TripProgressVehicle?
    let stops: [TripProgressStop]
    let segmentIndex: Int?
    let segmentFraction: Double?
    /// 0-1 fraction of the whole trip completed.
    let progress: Double?
    let nextStop: TripProgressStop?
    let scheduleDeviationSec: Int?
}
