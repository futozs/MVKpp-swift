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
        RideLiveActivity()
        WatchlistWidget()
        WatchlistControl()
        BoardedControl()
        NextBusControl()
    }
}
