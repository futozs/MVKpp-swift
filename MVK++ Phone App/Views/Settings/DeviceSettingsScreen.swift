//
//  DeviceSettingsScreen.swift
//  MVK++ Phone App
//

import SwiftUI
import WidgetKit

/// What only the iPhone has: the offline timetable, the base map, what the
/// Watch and the Smart Stack widget show, the watchlist order, and About.
/// Pushed from Beállítások ("Ezen az iPhone-on").
///
/// The watch and the widget have no UI of their own for this — the widget
/// literally says "pick a stop on the phone" until one is set — so this screen
/// is the only place these can be chosen.
struct DeviceSettingsScreen: View {

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject private var offlineSchedule = OfflineScheduleManager.shared

    var body: some View {
        Form {
            offlineSection
            watchSection
            watchlistSection
            aboutSection
        }
        .mvkBackground()
        .navigationTitle("Ezen az iPhone-on")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Offline & map

    /// Base map style picker alongside the offline timetable download — the
    /// timetable is the one thing here that still works without signal, since
    /// the base map is native Apple Maps and has no offline pack of its own.
    private var offlineSection: some View {
        Section {
            NavigationLink {
                BaseMapList(selectedLayerId: $navigation.tileLayerId)
                    .navigationTitle("Alaptérkép")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.hex(navigation.tileLayer.swatch, fallback: Theme.muted))
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                    Text("Alaptérkép")
                    Spacer(minLength: 8)
                    Text(navigation.tileLayer.name)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }

            NavigationLink {
                OfflineScheduleSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 26, height: 26)
                    Text("Menetrend letöltése")
                    Spacer(minLength: 8)
                    Text(scheduleSummary)
                        .foregroundStyle(offlineSchedule.manifest.isEmpty ? Theme.mutedForeground : Theme.primary)
                }
            }
        } header: {
            Label("Offline", systemImage: "wifi.slash")
        }
        .listRowBackground(Theme.card)
    }

    /// "7 nap" or "nincs" — enough to decide whether to tap in.
    private var scheduleSummary: String {
        if offlineSchedule.isDownloading { return "Letöltés…" }
        let days = offlineSchedule.manifest.days.count
        return days == 0 ? "Nincs" : "\(days) nap"
    }

    // MARK: - Watch and widget

    private var watchSection: some View {
        Section {
            if favorites.stopIds.isEmpty {
                Text("Nincs figyelt megálló")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.mutedForeground)
            } else {
                Toggle("Legközelebbi kedvenc a widgeten", isOn: $favorites.widgetNearestEnabled)
                    .tint(Theme.primary)

                Picker(favorites.widgetNearestEnabled ? "Tartalék megálló" : "Widget megálló", selection: widgetStopBinding) {
                    Text("Nincs").tag(String?.none)
                    ForEach(favorites.stopIds, id: \.self) { stopId in
                        Text(stopName(stopId)).tag(String?.some(stopId))
                    }
                }
                .pickerStyle(.navigationLink)
                .tint(Theme.primary)
            }

            Toggle("Legközelebbi megálló elöl", isOn: $favorites.nearestFirstEnabled)
                .tint(Theme.primary)
        } header: {
            Label("Óra és widget", systemImage: "applewatch")
        } footer: {
            if favorites.widgetNearestEnabled && !favorites.stopIds.isEmpty {
                Text("Az óra widgetje GPS alapján mindig a hozzád legközelebbi figyelt megállót mutatja. Ha nincs helyadat, a tartalék megálló jelenik meg. Nyisd meg egyszer az órán az MVK++ appot, hogy engedélyezd a helymeghatározást.")
            }
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Watchlist

    private var watchlistSection: some View {
        Section {
            LabeledContent("Figyelt megállók") {
                Text("\(favorites.stopIds.count) / \(FavoritesStore.maxCount)")
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }

            if !favorites.stopIds.isEmpty {
                // Reordering here is what the Watch reads when "nearest first"
                // is off, so it is worth being able to set deliberately.
                NavigationLink {
                    WatchlistOrderView()
                } label: {
                    Label("Sorrend és eltávolítás", systemImage: "arrow.up.arrow.down")
                }
            }
        } header: {
            Label("Megállófigyelő", systemImage: "dot.radiowaves.up.forward")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutScreen()
            } label: {
                Label("Névjegy", systemImage: "info.circle")
            }
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Bindings

    private var widgetStopBinding: Binding<String?> {
        Binding(
            get: { favorites.widgetStopId },
            set: { favorites.widgetStopId = $0 }
        )
    }

    private func stopName(_ stopId: String) -> String {
        store.stop(id: stopId)?.name ?? stopId
    }
}

/// Reorder and prune the watchlist. The order matters beyond this screen: it
/// is what the Watch shows when "nearest first" is switched off.
private struct WatchlistOrderView: View {
    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        List {
            ForEach(favorites.stopIds, id: \.self) { stopId in
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.stop(id: stopId)?.name ?? stopId)
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                    HStack(spacing: 6) {
                        Text(stopId)
                            .font(Theme.mono(11, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                        if favorites.widgetStopId == stopId {
                            Label("widget", systemImage: "applewatch")
                                .font(Theme.sans(10, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .onMove { source, destination in
                favorites.move(from: source, to: destination)
            }
            .onDelete { offsets in
                favorites.remove(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
        .mvkBackground()
        .navigationTitle("Sorrend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .environment(\.editMode, .constant(.active))
    }
}
