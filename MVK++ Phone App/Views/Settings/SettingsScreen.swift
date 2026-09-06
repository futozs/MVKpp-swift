//
//  SettingsScreen.swift
//  MVK++ Phone App
//

import SwiftUI
import WidgetKit

/// Where the phone configures the rest of the family: what the Watch shows,
/// which stop the Smart Stack widget counts down, and when the app is allowed
/// to interrupt.
///
/// The watch and the widget have no UI of their own for this — the widget
/// literally says "pick a stop on the phone" until one is set — so this screen
/// is the only place these can be chosen.
struct SettingsScreen: View {

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject private var notifications = NotificationCenterStore.shared

    @State private var isReloadingStops = false
    @State private var testSentAt: Date?

    var body: some View {
        NavigationStack {
            Form {
                mapSection
                watchSection
                watchlistSection
                notificationsSection
                serverSection
            }
            .mvkBackground()
            .navigationTitle("Beállítások")
            .task { await notifications.refreshAuthorization() }
        }
    }

    // MARK: - Base map

    private var mapSection: some View {
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
        } header: {
            Label("Térkép", systemImage: "map")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Watch and widget

    private var watchSection: some View {
        Section {
            if favorites.stopIds.isEmpty {
                Text("Nincs figyelt megálló")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.mutedForeground)
            } else {
                Picker("Widget megálló", selection: widgetStopBinding) {
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
            Text("Ezt számolja vissza az óra Smart Stackje és a telefon widgetje.")
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

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("Értesítések", isOn: $notifications.settings.enabled)
                .tint(Theme.primary)

            if notifications.authorization == .denied {
                Text("Az iOS letiltotta — engedélyezd a rendszerbeállításokban.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.destructive)
            }

            Toggle("Ne zavarjanak", isOn: $notifications.settings.dndEnabled)
                .tint(Theme.primary)

            if notifications.settings.dndEnabled {
                DatePicker("Kezdés", selection: dndStartBinding, displayedComponents: .hourAndMinute)
                DatePicker("Vége", selection: dndEndBinding, displayedComponents: .hourAndMinute)
            }

            LabeledContent("Beállított értesítések") {
                Text("\(notifications.watches.count)")
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }

            // Confirms permission and delivery in five seconds, instead of
            // waiting for a bus to find out whether any of it works.
            Button {
                Task {
                    await notifications.sendTestNotification()
                    testSentAt = Date()
                }
            } label: {
                Label("Teszt értesítés", systemImage: "bell.badge")
            }

            if testSentAt != nil {
                Text("Elküldve — 5 másodpercen belül megérkezik.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primary)
            }
        } header: {
            Label("Értesítések", systemImage: "bell")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Server

    private var serverSection: some View {
        Section {
            LabeledContent("Cím") {
                Text(APIConfig.baseURLString)
                    .font(Theme.mono(12, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
            }

            if let meta = store.gtfsMeta {
                LabeledContent("Menetrendi kiadás") {
                    Text(meta.feedVersion)
                        .font(Theme.mono(12, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                }
                LabeledContent("Megállók", value: "\(meta.stops)")
                LabeledContent("Járatok", value: "\(meta.routes)")
            }

            Button {
                Task {
                    isReloadingStops = true
                    await store.loadStatic()
                    isReloadingStops = false
                }
            } label: {
                if isReloadingStops {
                    ProgressView().tint(Theme.primary)
                } else {
                    Label("Menetrend frissítése", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isReloadingStops)
        } header: {
            Label("Szerver", systemImage: "server.rack")
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

    /// The stored value is minutes past midnight; the picker wants a Date, so
    /// both ends map onto an arbitrary day.
    private func minutesBinding(_ keyPath: WritableKeyPath<NotificationSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = notifications.settings[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                notifications.settings[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var dndStartBinding: Binding<Date> { minutesBinding(\.dndStartMin) }
    private var dndEndBinding: Binding<Date> { minutesBinding(\.dndEndMin) }

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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                    HStack(spacing: 6) {
                        Text(stopId)
                            .font(Theme.mono(11, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                        if favorites.widgetStopId == stopId {
                            Label("widget", systemImage: "applewatch")
                                .font(.system(size: 10, weight: .semibold))
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
