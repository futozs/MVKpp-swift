//
//  RootTabView.swift
//  MVK++ Phone App
//

import SwiftUI

/// The app shell (web `App.tsx` + `components/layout`): the glass header with
/// its banners on top, the six views, the glass tab bar at the bottom, and
/// the shell's dialogs.
///
/// Views are kept alive once visited, so each tab keeps its scroll position
/// and selection — except the Parkoló, which, like on the web, lives only
/// while it is open (its live subscription has no business running behind
/// the other tabs, and everything it remembers is stored).
extension EnvironmentValues {
    /// False while a visited tab stays mounted behind the active one: its
    /// live work (subscriptions, polls, timers) pauses until it is shown again.
    @Entry var isTabActive = true
}

struct RootTabView: View {
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var local = LocalStore.shared
    @StateObject private var weather = WeatherModel()
    @StateObject private var incidents = LiveIncidentsModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var visited: Set<AppTab> = []
    @State private var isLiveStatusOpen = false
    @State private var headerBottom: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isActive = navigation.tab == tab
                if isActive || (visited.contains(tab) && tab != .parking) {
                    screen(tab)
                        .environment(\.isTabActive, isActive)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .accessibilityHidden(!isActive)
                        .zIndex(isActive ? 1 : 0)
                }
            }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                AppHeader(weather: weather, isLiveStatusOpen: $isLiveStatusOpen)
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }) { headerBottom = $0 }
                SyncBanner()
                RegionalIntroBanner()
            }
            .padding(.bottom, 4)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            AppTabBar(
                selection: $navigation.tab,
                counts: TabCounts(monitoredStops: shownMonitoredCount, liveIncidents: incidents.count),
                showBadges: local.showsTabBadges
            )
        }
        .overlay(alignment: .top) { liveStatusPanel }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $navigation.isSettingsOpen) { SettingsSheet().mvkDialog(cornerRadius: Theme.Radius.xl) }
        .sheet(isPresented: $navigation.isNotificationsOpen) { NotificationsSheet().mvkDialog(cornerRadius: Theme.Radius.xl) }
        .sheet(isPresented: $navigation.isAccountOpen) { AccountSheet().mvkDialog(cornerRadius: Theme.Radius.xl) }
        .sheet(isPresented: $navigation.isDisruptionsOpen) { DisruptionsSheet().mvkDialog() }
        .fullScreenCover(isPresented: kioskBinding) {
            KioskScreen(stopIds: navigation.kioskStopIds ?? []) { navigation.kioskStopIds = nil }
        }
        .onAppear { visited.insert(navigation.tab) }
        .onChange(of: navigation.tab) { _, tab in
            visited.insert(tab)
            UsageReporter.shared.track(tab.rawValue)
        }
        .onChange(of: store.stops) { _, _ in foldMergedTwins() }
        .onChange(of: local.stopMerge) { _, _ in foldMergedTwins() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.wake()
                CloudSync.shared.didBecomeActive()
                Task { await NotificationCenterStore.shared.refreshAuthorization() }
            case .background:
                CloudSync.shared.didEnterBackground()
                UsageReporter.shared.flush()
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
        .task {
            weather.start()
            incidents.start()
            store.startLive()
            UsageReporter.shared.start()
            UsageReporter.shared.track(navigation.tab.rawValue)
            await store.loadStaticIfNeeded()
            location.startIfPermitted()
            // Once the app has been opened, it has the timetable. Nothing on
            // screen waits for this, and a device with the current release
            // does no work at all.
            await OfflineScheduleManager.shared.refreshIfNeeded(meta: store.gtfsMeta)
        }
    }

    @ViewBuilder
    private func screen(_ tab: AppTab) -> some View {
        switch tab {
        case .map: MapScreen()
        case .multistop: MultiStopScreen()
        case .timetable: TimetableScreen()
        case .parking: ParkingScreen()
        case .planner: RoutePlannerScreen()
        case .stats: StatsScreen()
        }
    }

    /// The live pill's panel: 2 pt under the header, 8 pt from the edges; a
    /// tap anywhere else closes it.
    private var liveStatusPanel: some View {
        ZStack(alignment: .top) {
            if isLiveStatusOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isLiveStatusOpen = false }
                    .accessibilityHidden(true)
                LiveStatusPanel(
                    vehicleCount: store.liveVehicles.count,
                    lastUpdated: store.lastUpdated,
                    isRefreshing: store.isRefreshing,
                    weather: weather.weather,
                    onRefresh: { Task { await store.refreshLive() } }
                )
                .padding(.horizontal, 8)
                .padding(.top, headerBottom + 2)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)).combined(with: .offset(y: -4)))
            }
        }
        .ignoresSafeArea()
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.14), value: isLiveStatusOpen)
    }

    private var kioskBinding: Binding<Bool> {
        Binding(get: { navigation.kioskStopIds != nil }, set: { if !$0 { navigation.kioskStopIds = nil } })
    }

    /// A switched-off mode's stops (a railway station in MVK-only mode) do
    /// not count in the tab badge.
    private var shownMonitoredCount: Int {
        let enabled = local.enabledModes
        return favorites.stopIds.filter { id in
            switch TransitModes.feed(ofId: id) {
            case .mvk: return true
            case .coach: return enabled.contains(.coach)
            case .rail: return enabled.contains(.rail)
            }
        }.count
    }

    /// Merged stops: an old watchlist entry for a Volán twin moves to its MVK
    /// pole, or the same board would show twice.
    private func foldMergedTwins() {
        guard local.stopMerge != .off else { return }
        let twinOf = Dictionary(store.stops.compactMap { stop in stop.twinOf.map { (stop.id, $0) } }, uniquingKeysWith: { first, _ in first })
        guard !twinOf.isEmpty, favorites.stopIds.contains(where: { twinOf[$0] != nil }) else { return }
        var seen = Set<String>()
        let folded = favorites.stopIds.map { twinOf[$0] ?? $0 }.filter { seen.insert($0).inserted }
        favorites.setStopIds(folded)
    }
}

