//
//  WatchWidgetIntents.swift
//  MVK++ Widget
//

import AppIntents
import WidgetKit

/// Which stop a complication follows. No stop means the phone's pick, or
/// the nearest watched stop when that is switched on.
struct WatchStopConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Megálló"
    static let description = IntentDescription("Melyik megálló indulásait mutassa a számlap.")

    @Parameter(title: "Megálló")
    var stop: StopEntity?

    init() {}

    init(stop: StopEntity?) {
        self.stop = stop
    }
}
