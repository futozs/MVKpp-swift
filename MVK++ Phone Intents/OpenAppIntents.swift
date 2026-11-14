//
//  OpenAppIntents.swift
//  MVK++ Phone Intents (shared by the Phone app and its widget)
//

import AppIntents
import Foundation

/// Where in the app a control or a shortcut lands.
enum AppDestination: String, AppEnum {
    case watchlist, ride, map, timetable, disruptions

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Képernyő"
    static let caseDisplayRepresentations: [AppDestination: DisplayRepresentation] = [
        .watchlist: "Figyelő",
        .ride: "Felszálltam",
        .map: "Térkép",
        .timetable: "Menetrend",
        .disruptions: "Mai zavarok",
    ]

    var link: DeepLink {
        switch self {
        case .watchlist: return .tab(.multistop)
        case .ride: return .ride
        case .map: return .tab(.map)
        case .timetable: return .tab(.timetable)
        case .disruptions: return .disruptions
        }
    }
}

/// Opens the app on one screen through its `mvkpp://` link, so a control
/// lands exactly where a widget tap would.
struct OpenAppScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "MVK++ megnyitása"
    static let description = IntentDescription("Megnyitja az MVK++-t a kiválasztott képernyőn.")
    static let openAppWhenRun = true

    @Parameter(title: "Képernyő", default: .watchlist)
    var destination: AppDestination

    init() {}

    init(_ destination: AppDestination) {
        self.destination = destination
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(destination.link.url))
    }
}

/// "Felszálltam" from the Control Center, the Action button or Siri: the
/// app opens on the ride, or on picking the bus.
struct BoardedIntent: AppIntent {
    static let title: LocalizedStringResource = "Felszálltam"
    static let description = IntentDescription("Elindítja az utazást az MVK++-ban.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.ride.url))
    }
}

/// The stop the phone's controls follow: the watched stop nearest to where
/// the app last saw the rider, then the widget's pick, then the first one.
enum ControlStopResolver {
    static func stopId() -> String? {
        let watched = FavoritesStore.storedStopIds
        if let fix = LocationProvider.sharedLastFix(maxAge: 2 * 60 * 60) {
            let wanted = Set(watched)
            let stops = SharedStopCache.load().filter { wanted.contains($0.id) }
            if let nearest = stops.min(by: {
                Geo.distanceKm(fix.lat, fix.lon, $0.lat, $0.lon) < Geo.distanceKm(fix.lat, fix.lon, $1.lat, $1.lon)
            }) {
                return nearest.id
            }
        }
        return FavoritesStore.storedWidgetStopId ?? watched.first
    }
}
