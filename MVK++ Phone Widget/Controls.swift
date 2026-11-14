//
//  Controls.swift
//  MVK++ Phone Widget
//

import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button controls.

struct WatchlistControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "hu.futozs.mvk.control.watchlist") {
            ControlWidgetButton(action: OpenAppScreenIntent(.watchlist)) {
                Label("Figyelő", systemImage: "dot.radiowaves.up.forward")
            }
        }
        .displayName("Figyelő")
        .description("Megnyitja a figyelt megállóidat.")
    }
}

struct BoardedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "hu.futozs.mvk.control.ride") {
            ControlWidgetButton(action: BoardedIntent()) {
                Label("Felszálltam", systemImage: "ticket")
            }
        }
        .displayName("Felszálltam")
        .description("Elindítja az utazást: kiválasztod a buszt, és szól a leszállás előtt.")
    }
}

/// The next bus at the nearest watched stop, written on the control itself.
struct NextBusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "hu.futozs.mvk.control.nextbus", provider: NextBusValueProvider()) { value in
            ControlWidgetButton(action: OpenAppScreenIntent(.watchlist)) {
                Label {
                    Text(value.title)
                    Text(value.subtitle)
                } icon: {
                    Image(systemName: value.isTram ? "tram.fill" : "bus.fill")
                }
            }
        }
        .displayName("Következő busz")
        .description("A legközelebbi figyelt megálló következő indulása.")
    }
}

struct NextBusValue {
    let title: String
    let subtitle: String
    let isTram: Bool
}

struct NextBusValueProvider: ControlValueProvider {
    var previewValue: NextBusValue {
        NextBusValue(title: "1 · 3 perc", subtitle: "Búza tér", isTram: true)
    }

    func currentValue() async throws -> NextBusValue {
        guard let stopId = ControlStopResolver.stopId() else {
            return NextBusValue(title: "Figyelő", subtitle: "Nincs figyelt megálló", isTram: false)
        }
        let response = try await APIClient.shared.arrivals(stopId: stopId, limit: 2, boardKey: WatchSharedState.settings.boardKey)
        let name = response.stop.name ?? stopId
        guard let next = response.arrivals.first(where: { !$0.isCancelled }) else {
            return NextBusValue(title: "Nincs induló járat", subtitle: name, isTram: false)
        }
        let when = next.etaMin <= 0 ? "most" : "\(next.etaMin) perc"
        return NextBusValue(title: "\(next.route) · \(when)", subtitle: name, isTram: next.mode == .tram)
    }
}
