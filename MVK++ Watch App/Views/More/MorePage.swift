//
//  MorePage.swift
//  MVK++ Watch App
//

import SwiftUI

/// Továbbiak: the rest of the app, one tap each.
struct MorePage: View {
    @EnvironmentObject private var router: WatchRouter
    @EnvironmentObject private var link: WatchLink

    var body: some View {
        List {
            row(link.ride == nil ? "Felszálltam" : "Utazás", icon: "ticket", tint: Theme.primary) {
                router.push(link.ride == nil ? .boardPicker : .ride)
            }
            row("Térkép", icon: "map.fill", tint: Theme.early) { router.push(.map) }
            row("Menetrend", icon: "calendar", tint: Theme.signal300) { router.push(.timetable) }
            row("Mai zavarok", icon: "exclamationmark.triangle.fill", tint: Theme.late) { router.push(.disruptions) }
            row("Hírek", icon: "newspaper.fill", tint: Theme.amber400) { router.push(.news) }
            row("Keresés", icon: "magnifyingglass", tint: Theme.mutedForeground) { router.push(.search) }
            row("Beállítások", icon: "gearshape.fill", tint: Theme.mutedForeground) { router.push(.settings) }
        }
        .navigationTitle("MVK++")
        .containerBackground(Theme.signal900.gradient, for: .tabView)
    }

    private func row(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
        }
    }
}
