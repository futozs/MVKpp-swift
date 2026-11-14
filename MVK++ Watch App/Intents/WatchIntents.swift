//
//  WatchIntents.swift
//  MVK++ Watch App
//

import AppIntents
import SwiftUI

/// "Mikor jön a busz?" — the next departures at a stop: the one asked for,
/// or else the watched stop nearest to the rider. For Siri, the Smart Stack
/// and the Action button.
struct NextDepartureIntent: AppIntent {
    static let title: LocalizedStringResource = "Következő indulás"
    static let description = IntentDescription("A megálló következő indulásai — megálló nélkül a legközelebbi figyelt megállóé.")

    @Parameter(title: "Megálló")
    var stop: StopEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Következő indulás innen: \(\.$stop)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let stopId = await resolvedStopId() else {
            return .result(dialog: "Még nincs figyelt megállód.", view: EmptyView())
        }
        let boardKey = WatchSharedState.settings.boardKey
        do {
            let response = try await APIClient.shared.arrivals(stopId: stopId, limit: 3, boardKey: boardKey)
            let name = response.stop.name ?? stop?.name ?? stopId
            guard let next = response.arrivals.first(where: { !$0.isCancelled }) else {
                return .result(dialog: "\(name): innen ma már nem indul járat.", view: EmptyView())
            }
            let when = next.etaMin <= 0 ? "most indul" : "\(next.etaMin) perc múlva indul"
            return .result(
                dialog: "\(name): a \(next.route) \(next.headsign) felé \(when).",
                view: DepartureSnippet(name: name, arrivals: Array(response.arrivals.prefix(3)))
            )
        } catch {
            return .result(dialog: "Most nem érem el az MVK-t.", view: EmptyView())
        }
    }

    private func resolvedStopId() async -> String? {
        if let stop { return stop.id }
        return await WidgetStopResolver.resolveStopId() ?? FavoritesStore.storedStopIds.first
    }
}

/// By the number on the stop sign: "mikor jön a busz a 84-re".
struct NextBusIntent: AppIntent {
    static let title: LocalizedStringResource = "Indulás megállószám alapján"
    static let description = IntentDescription("A megállótáblán lévő szám alapján mondja meg a következő indulást.")

    @Parameter(title: "Megállószám")
    var stopCode: StopCodeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Következő indulás a(z) \(\.$stopCode) megállóból")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let stopId = "SP\(stopCode.id)"
        do {
            let response = try await APIClient.shared.arrivals(stopId: stopId, limit: 3, boardKey: WatchSharedState.settings.boardKey)
            let name = response.stop.name ?? "\(stopCode.id). megálló"
            guard let next = response.arrivals.first(where: { !$0.isCancelled }) else {
                return .result(dialog: "\(name): innen most nem indul járat.", view: EmptyView())
            }
            let when = next.etaMin <= 0 ? "most indul" : "\(next.etaMin) perc múlva indul"
            return .result(
                dialog: "\(name): a \(next.route) \(next.headsign) felé \(when).",
                view: DepartureSnippet(name: name, arrivals: Array(response.arrivals.prefix(3)))
            )
        } catch {
            return .result(dialog: "A(z) \(stopCode.id). megállót most nem érem el.", view: EmptyView())
        }
    }
}

/// App Intents wants an entity, not a bare number, for a parameter spoken
/// inside a Siri phrase.
struct StopCodeEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Megállószám")
    static let defaultQuery = StopCodeEntityQuery()

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

/// "Felszálltam": opens the watch on the buses leaving around the rider, or
/// on the ride already running.
struct StartRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Felszálltam"
    static let description = IntentDescription("Elindítja az utazást: kiválasztod a buszt, és az óra jelez a leszállás előtt.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let ride = WatchLink.shared.ride
        WatchRouter.shared.show(ride == nil || ride?.ended == true ? .boardPicker : .ride)
        return .result()
    }
}

/// Opens the Figyelő — for the Action button and the Smart Stack.
struct OpenWatchlistIntent: AppIntent {
    static let title: LocalizedStringResource = "Figyelő megnyitása"
    static let description = IntentDescription("A figyelt megállóid élő indulásai.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRouter.shared.page = .watchlist
        WatchRouter.shared.popToRoot()
        return .result()
    }
}

struct MVKShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextDepartureIntent(),
            phrases: [
                "Mikor jön a busz \(.applicationName)",
                "\(.applicationName) következő indulás",
                "When is the next bus \(.applicationName)",
                "\(.applicationName) next bus",
            ],
            shortTitle: "Következő indulás",
            systemImageName: "bus.fill"
        )
        AppShortcut(
            intent: NextBusIntent(),
            phrases: [
                "\(.applicationName) megállószám \(\.$stopCode)",
                "When will the bus come to \(.applicationName) \(\.$stopCode)",
                "\(.applicationName) when is the next bus at \(\.$stopCode)",
            ],
            shortTitle: "Megállószám",
            systemImageName: "number"
        )
        AppShortcut(
            intent: StartRideIntent(),
            phrases: [
                "Felszálltam \(.applicationName)",
                "\(.applicationName) felszálltam",
                "\(.applicationName) I'm on the bus",
            ],
            shortTitle: "Felszálltam",
            systemImageName: "ticket"
        )
        AppShortcut(
            intent: OpenWatchlistIntent(),
            phrases: [
                "\(.applicationName) Figyelő",
                "Open \(.applicationName) watchlist",
            ],
            shortTitle: "Figyelő",
            systemImageName: "dot.radiowaves.up.forward"
        )
    }
}

/// What Siri shows under the answer.
struct DepartureSnippet: View {
    let name: String
    let arrivals: [ArrivalItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
            ForEach(arrivals) { arrival in
                DepartureRow(arrival: arrival, showsVehicle: false)
            }
        }
        .padding(.vertical, 4)
    }
}
