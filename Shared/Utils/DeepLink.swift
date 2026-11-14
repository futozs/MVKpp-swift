//
//  DeepLink.swift
//  MVK++ (shared by the Phone, Watch and Widget targets)
//

import Foundation

/// The `mvkpp://` URL space. The widget builds these; the phone app resolves
/// them in `onOpenURL`.
///
/// Kept as one small enum on both sides so a tap on a widget row can never
/// land on a URL the app does not understand.
enum DeepLink: Equatable {
    /// Open the map on a stop and show its arrivals sheet.
    case stop(String)
    /// Open the Megállófigyelő on a stop, adding it to the watchlist if it
    /// is not there yet. This is where a widget tap lands.
    case watchlist(String)
    /// Open the map and lock on to a running vehicle.
    case trip(tripId: String, vehicleId: String?)
    /// Just bring the app forward.
    case home
    /// One of the six views (the web's `#stats`, `#parking` … hash links).
    case tab(AppTab)
    /// "Felszálltam": the ride in progress, or the boarding flow without one.
    case ride
    /// Mai zavarok.
    case disruptions

    static let scheme = "mvkpp"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .stop(let stopId):
            components.host = "stop"
            components.path = "/\(stopId)"
        case .watchlist(let stopId):
            components.host = "watch"
            components.path = "/\(stopId)"
        case .trip(let tripId, let vehicleId):
            components.host = "trip"
            components.path = "/\(tripId)"
            if let vehicleId, !vehicleId.isEmpty {
                components.queryItems = [URLQueryItem(name: "vehicle", value: vehicleId)]
            }
        case .home:
            components.host = "home"
            components.path = ""
        case .tab(let tab):
            components.host = "tab"
            components.path = "/\(tab.rawValue)"
        case .ride:
            components.host = "ride"
            components.path = ""
        case .disruptions:
            components.host = "disruptions"
            components.path = ""
        }
        // Every case above produces a well-formed URL; the fallback exists
        // only so callers do not have to handle an impossible optional.
        return components.url ?? URL(string: "\(Self.scheme)://home")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let value = url.pathComponents.first { $0 != "/" }

        switch url.host {
        case "stop":
            guard let value, !value.isEmpty else { return nil }
            self = .stop(value)
        case "watch":
            guard let value, !value.isEmpty else { return nil }
            self = .watchlist(value)
        case "trip":
            guard let value, !value.isEmpty else { return nil }
            let vehicle = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "vehicle" }?.value
            self = .trip(tripId: value, vehicleId: vehicle)
        case "home":
            self = .home
        case "tab":
            guard let value, let tab = AppTab(rawValue: value) else { return nil }
            self = .tab(tab)
        case "ride":
            self = .ride
        case "disruptions":
            self = .disruptions
        default:
            return nil
        }
    }
}
