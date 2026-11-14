//
//  SelectStopIntent.swift
//  MVK++ Phone Intents (shared by the Phone app and its widget)
//

import AppIntents
import Foundation

/// The widget's own configuration.
struct SelectStopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Megálló"
    static let description = IntentDescription("Melyik megálló indulásait mutassa a widget.")

    @Parameter(title: "Megálló")
    var stop: StopEntity?

    /// Riders who track a specific vehicle care about the plate; riders who
    /// just want the next bus find it noise. Default on — it is one of the
    /// things this widget exists to show.
    @Parameter(title: "Rendszám mutatása", default: true)
    var showsVehicle: Bool

    init() {}

    init(stop: StopEntity?, showsVehicle: Bool = true) {
        self.stop = stop
        self.showsVehicle = showsVehicle
    }
}
