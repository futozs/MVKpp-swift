//
//  MVKPhoneWidgetBundle.swift
//  MVK++ Phone Widget
//

import SwiftUI
import WidgetKit

@main
struct MVKPhoneWidgetBundle: WidgetBundle {
    var body: some Widget {
        StopDeparturesWidget()
        WatchlistWidget()
        WatchlistControl()
        BoardedControl()
        NextBusControl()
    }
}
