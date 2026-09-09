//
//  StopDeparturesWidget.swift
//  MVK++ Phone Widget
//

import SwiftUI
import WidgetKit

/// "Következő indulások" — the configurable home screen widget.
///
/// Deliberately no `.systemSmall`: a square has room for one route and a
/// number, which is the watch's job. This one is a departure board, and a
/// board needs width.
struct StopDeparturesWidget: Widget {
    let kind = "StopDeparturesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectStopIntent.self,
            provider: StopDeparturesProvider()
        ) { entry in
            StopDeparturesView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Theme.card, Theme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Következő indulások")
        .description("Egy megálló élő indulásai: melyik járat, milyen rendszámmal, mennyit késik, és hány perc múlva ér oda.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

#Preview("Medium", as: .systemMedium) {
    StopDeparturesWidget()
} timeline: {
    StopDeparturesEntry.placeholder()
}

#Preview("Large", as: .systemLarge) {
    StopDeparturesWidget()
} timeline: {
    StopDeparturesEntry.placeholder()
}
