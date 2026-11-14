//
//  RideActivity.swift
//  MVK++ Phone Intents (shared by the Phone app and its widget)
//
//  The ride in progress as a Live Activity: the app updates it locally while
//  the ride runs; the widget extension draws it on the Lock Screen and in
//  the Dynamic Island.
//

import ActivityKit
import AppIntents
import Foundation

struct RideActivityAttributes: ActivityAttributes {
    /// Field names match the server's Live Activity push channel, so a push
    /// decodes into the same state; the ride-only extras are optional.
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            /// The trip's stops are loading or the rider has not picked the stops yet.
            case setup
            case riding
            /// Loop journey: waiting at the terminus for the next trip.
            case turn
        }

        var tripId: String
        var vehicleId: String?
        var live: Bool
        /// 0…1 from boarding to the destination (or the terminus).
        var progress: Double?
        var delaySec: Int?
        /// The stop the bus reaches next.
        var nextStopId: String?
        var nextStopName: String?
        var nextStopEtaUnix: Double?
        /// Stops still to go to the destination.
        var stopsLeft: Int?
        /// Expected arrival at the destination (unix).
        var stopEtaUnix: Double?
        var speedKmh: Int?
        var ended: Bool
        var updatedAt: Double

        var phase: Phase?
        /// Where the rider gets off (nil: not chosen, or a loop journey).
        var destName: String?
        /// Loop journey: which leg, and the terminus where the bus turns.
        var leg: Int?
        var turnName: String?

        var nextStopAt: Date? { nextStopEtaUnix.map { Date(timeIntervalSince1970: $0) } }
        var destAt: Date? { stopEtaUnix.map { Date(timeIntervalSince1970: $0) } }
    }

    var route: String
    var color: String
    var text: String
    var headsign: String
    var vehicleLabel: String
    /// „busz”, „villamos”, „vonat”.
    var vehicleNoun: String
}

/// The app sets this at launch; the intent below runs in the app's process.
enum RideIntentBridge {
    @MainActor static var alight: (() -> Void)?
}

/// „Leszálltam” from the Live Activity and Shortcuts.
struct AlightRideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Leszálltam"
    static let description = IntentDescription("Lezárja a folyamatban lévő utazást ott, ahol a busz most tart.")

    @MainActor
    func perform() async throws -> some IntentResult {
        RideIntentBridge.alight?()
        return .result()
    }
}
