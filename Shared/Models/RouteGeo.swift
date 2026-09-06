//
//  RouteGeo.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import CoreLocation
import Foundation

/// A route with its drawable shapes, from `/gtfs/route-geo`. One route can
/// have several disjoint shapes (variants, short turns), hence the nesting.
struct RouteGeo: Decodable, Identifiable, Hashable {
    let id: String
    let short: String
    let long: String
    let type: String
    let color: String
    let text: String
    /// Each shape is an ordered list of `[lat, lon]` pairs.
    let shapes: [[[Double]]]
    let stops: [String]

    var polylines: [[CLLocationCoordinate2D]] {
        shapes.map { shape in
            shape.compactMap { point in
                guard point.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
            }
        }
    }
}

struct RouteGeoResponse: Decodable {
    let routes: [RouteGeo]
}
