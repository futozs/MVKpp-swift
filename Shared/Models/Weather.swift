//
//  Weather.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// `/weather` — current conditions over the service area.
struct WeatherResponse: Decodable, Hashable {
    let tempC: Double?
    let feelsLikeC: Double?
    let windKmh: Double?
    let code: Int
    let text: String
    let at: String
}
