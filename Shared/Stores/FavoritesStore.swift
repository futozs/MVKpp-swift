//
//  FavoritesStore.swift
//  MVK++ (shared by the Watch and Phone targets)
//

import Combine
import Foundation
import SwiftUI
import WidgetKit

/// Watched stop IDs + the "nearest first" toggle + the single stop shown on
/// the watch's Smart Stack widget, mirroring the web app's
/// `mvk_monitored_stops` / `mvk_watch_nearest_first` localStorage keys.
///
/// Backed by the App Group suite for same-device persistence, and by
/// `WatchLink` (WatchConnectivity) for cross-device sync — an App Group alone
/// only shares storage between apps on the *same* device, which does nothing
/// for a Watch and its paired iPhone (two separate devices/OSes).
@MainActor
final class FavoritesStore: ObservableObject {
    /// How many stops the watch's own code entry may add. The list itself has
    /// no cap (like the web's), and it syncs whole: a capped copy coming back
    /// from the watch would drop the phone's extra stops.
    static let maxCount = 12
    static let appGroupID = "group.hu.futozs.mvk"
    nonisolated static let widgetStopKey = "mvk_widget_stop_id"
    nonisolated static let widgetNearestKey = "mvk_widget_nearest_favorite"
    nonisolated private static let storageKey = "mvk_monitored_stops"
    private static let nearestFirstKey = "mvk_watch_nearest_first"
    nonisolated private static let suite = UserDefaults(suiteName: appGroupID) ?? .standard

    @Published private(set) var stopIds: [String]
    @Published var nearestFirstEnabled: Bool {
        didSet {
            guard nearestFirstEnabled != oldValue else { return }
            Self.suite.set(nearestFirstEnabled, forKey: Self.nearestFirstKey)
            pushContext()
        }
    }
    @Published var widgetStopId: String? {
        didSet {
            guard widgetStopId != oldValue else { return }
            Self.suite.set(widgetStopId, forKey: Self.widgetStopKey)
            WidgetCenter.shared.reloadAllTimelines()
            pushContext()
        }
    }
    /// The watch widget follows the rider: it shows whichever watched stop
    /// is closest to the current GPS fix instead of the fixed `widgetStopId`
    /// (which stays as the fallback when there is no position).
    @Published var widgetNearestEnabled: Bool {
        didSet {
            guard widgetNearestEnabled != oldValue else { return }
            Self.suite.set(widgetNearestEnabled, forKey: Self.widgetNearestKey)
            WidgetCenter.shared.reloadAllTimelines()
            pushContext()
        }
    }

    /// The watchlist as stored, readable without the main actor.
    ///
    /// Widget extensions need the list to rank a stop picker, and must not
    /// instantiate the store to get it — that would activate a `WCSession`
    /// inside an extension for no reason.
    nonisolated static var storedStopIds: [String] {
        (suite.array(forKey: storageKey) as? [String]) ?? []
    }

    nonisolated static var storedWidgetStopId: String? {
        suite.string(forKey: widgetStopKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    nonisolated static var storedWidgetNearestEnabled: Bool {
        suite.bool(forKey: widgetNearestKey)
    }

    private var cancellable: AnyCancellable?

    init() {
        stopIds = (Self.suite.array(forKey: Self.storageKey) as? [String]) ?? ["SP1"]
        nearestFirstEnabled = Self.suite.bool(forKey: Self.nearestFirstKey)
        widgetStopId = Self.suite.string(forKey: Self.widgetStopKey)
        widgetNearestEnabled = Self.suite.bool(forKey: Self.widgetNearestKey)
        cancellable = WatchLink.shared.received.sink { [weak self] payload in
            self?.apply(payload)
        }
        WatchLink.shared.activate()
        pushContext()
    }

    func add(_ stopId: String) {
        guard !stopIds.contains(stopId) else { return }
        stopIds.append(stopId)
        persist()
    }

    func contains(_ stopId: String) -> Bool { stopIds.contains(stopId) }

    /// Adds or removes in one call — what a "watch this stop" control needs.
    func toggle(_ stopId: String) {
        if stopIds.contains(stopId) {
            remove(stopId)
        } else {
            add(stopId)
        }
    }

    func remove(_ stopId: String) {
        stopIds.removeAll { $0 == stopId }
        if widgetStopId == stopId { widgetStopId = nil }
        persist()
    }

    func remove(at offsets: IndexSet) {
        let removed = offsets.map { stopIds[$0] }
        stopIds.remove(atOffsets: offsets)
        if let widgetStopId, removed.contains(widgetStopId) { self.widgetStopId = nil }
        persist()
    }

    /// Replaces the whole list in one write (merged twin stops folding into
    /// their MVK pole).
    func setStopIds(_ ids: [String]) {
        guard ids != stopIds else { return }
        stopIds = ids
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        stopIds.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        Self.suite.set(stopIds, forKey: Self.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
        pushContext()
    }

    private func pushContext() {
        var values: [String: Any] = [
            WatchSyncKey.stopIds: stopIds,
            WatchSyncKey.nearestFirst: nearestFirstEnabled,
            WatchSyncKey.widgetNearest: widgetNearestEnabled,
        ]
        values[WatchSyncKey.widgetStopId] = widgetStopId
        WatchLink.shared.update(values, removing: widgetStopId == nil ? [WatchSyncKey.widgetStopId] : [])
    }

    /// The other device's watchlist, as it arrives.
    private func apply(_ payload: [String: Any]) {
        guard payload.keys.contains(WatchSyncKey.stopIds) else { return }
        if let remote = payload[WatchSyncKey.stopIds] as? [String], remote != stopIds {
            stopIds = remote
            Self.suite.set(remote, forKey: Self.storageKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
        if let nearestFirst = payload[WatchSyncKey.nearestFirst] as? Bool {
            nearestFirstEnabled = nearestFirst
        }
        if let widgetNearest = payload[WatchSyncKey.widgetNearest] as? Bool {
            widgetNearestEnabled = widgetNearest
        }
        let remoteWidgetStop = payload[WatchSyncKey.widgetStopId] as? String
        if remoteWidgetStop != widgetStopId {
            widgetStopId = remoteWidgetStop
        }
    }
}
