//
//  RootTabView.swift
//  MVK++ Phone App
//

import SwiftUI

/// The app's four surfaces, in the same order as the web app's tab bar, plus
/// the settings the phone owns on the Watch's behalf.
///
/// The tab bar minimises as the rider scrolls, so a full-bleed map and a long
/// timetable both get the whole screen when they need it.
struct RootTabView: View {
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var location: LocationProvider

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Térkép", systemImage: "map.fill", value: AppTab.map) {
                MapScreen()
            }

            Tab("Megállók", systemImage: "dot.radiowaves.up.forward", value: AppTab.multistop) {
                MultiStopScreen()
            }

            Tab("Menetrend", systemImage: "calendar", value: AppTab.timetable) {
                TimetableScreen()
            }

            Tab("Tervező", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill", value: AppTab.planner) {
                RoutePlannerScreen()
            }

            // The Watch and the widget have no settings UI of their own —
            // which stop the Smart Stack counts down is chosen here.
            Tab("Beállítások", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.primary)
        .task {
            await store.loadStaticIfNeeded()
            location.startIfPermitted()
            // Once the app has been opened, it has the timetable. This runs
            // behind the tab bar and only when there is a reason to — nothing
            // on screen waits for it, and a device that already has the
            // current release does no work at all.
            await OfflineScheduleManager.shared.refreshIfNeeded(meta: store.gtfsMeta)
        }
    }
}
