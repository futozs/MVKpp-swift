//
//  NextBusIntent.swift
//  MVK++ Watch App
//

import AppIntents

/// Wraps a bare number as an AppEntity — App Intents on watchOS requires
/// AppEntity/AppEnum (not a raw Int) for any parameter embedded directly in
/// a Siri phrase, even though the value itself is just "the stop's number".
struct StopCodeEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Stop Code")
    static var defaultQuery = StopCodeEntityQuery()

    let id: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct StopCodeEntityQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [StopCodeEntity] {
        identifiers.map { StopCodeEntity(id: $0) }
    }
}

/// Siri: "When will the bus come to eighty four?" — the number is the
/// rider-facing stop code embedded in its id (e.g. "SP84").
struct NextBusIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Bus Arrival"
    static var description = IntentDescription("Tells you when the next bus arrives at a stop, by its numeric code.")

    @Parameter(title: "Stop Code")
    var stopCode: StopCodeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("When will the bus come to \(\.$stopCode)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stopId = "SP\(stopCode.id)"
        do {
            let response = try await APIClient.shared.arrivals(stopId: stopId, limit: 1)
            guard let arrival = response.arrivals.first else {
                return .result(dialog: "There's no upcoming departure from stop \(stopCode.id) right now.")
            }
            let stopName = response.stop.name ?? "stop \(stopCode.id)"
            let etaPhrase = arrival.etaMin <= 0
                ? "arriving now"
                : "arriving in \(arrival.etaMin) minute\(arrival.etaMin == 1 ? "" : "s")"
            return .result(dialog: "Route \(arrival.route) towards \(arrival.headsign) is \(etaPhrase) at \(stopName).")
        } catch {
            return .result(dialog: "I couldn't reach stop \(stopCode.id) right now.")
        }
    }
}

struct MVKShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextBusIntent(),
            phrases: [
                "When will the bus come to \(.applicationName) \(\.$stopCode)",
                "\(.applicationName) when is the next bus at \(\.$stopCode)",
                "Ask \(.applicationName) when the bus comes to \(\.$stopCode)",
            ],
            shortTitle: "Next Bus",
            systemImageName: "bus.fill"
        )
    }
}
