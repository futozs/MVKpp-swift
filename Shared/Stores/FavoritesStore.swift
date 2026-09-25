//
//  FavoritesStore.swift
//  MVK++ (shared by the Watch and Phone targets)
//

import Combine
import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit

/// Watched stop IDs + the "nearest first" toggle + the single stop shown on
/// the watch's Smart Stack widget, mirroring the web app's
/// `mvk_monitored_stops` / `mvk_watch_nearest_first` localStorage keys.
///
/// Backed by the App Group suite for same-device persistence, and by
/// `WatchConnectivity` for cross-device sync — an App Group alone only
/// shares storage between apps on the *same* device, which does nothing
/// for a Watch and its paired iPhone (two separate devices/OSes).
@MainActor
final class FavoritesStore: NSObject, ObservableObject {
    /// The web app lets riders watch as many stops as they like; twelve is
    /// where a phone carousel stops being navigable, and it is far above what
    /// anyone puts on a watch.
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

    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    override init() {
        stopIds = (Self.suite.array(forKey: Self.storageKey) as? [String]) ?? ["SP1"]
        nearestFirstEnabled = Self.suite.bool(forKey: Self.nearestFirstKey)
        widgetStopId = Self.suite.string(forKey: Self.widgetStopKey)
        widgetNearestEnabled = Self.suite.bool(forKey: Self.widgetNearestKey)
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func add(_ stopId: String) {
        guard !stopIds.contains(stopId), stopIds.count < Self.maxCount else { return }
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
        guard let session, session.activationState == .activated else { return }
        var context: [String: Any] = [
            "stopIds": stopIds,
            "nearestFirstEnabled": nearestFirstEnabled,
            "widgetNearestEnabled": widgetNearestEnabled,
        ]
        context["widgetStopId"] = widgetStopId
        try? session.updateApplicationContext(context)
    }
}

extension FavoritesStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushContext() }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let stopIds = applicationContext["stopIds"] as? [String], stopIds != self.stopIds {
                self.stopIds = stopIds
                Self.suite.set(stopIds, forKey: Self.storageKey)
            }
            if let nearestFirst = applicationContext["nearestFirstEnabled"] as? Bool {
                self.nearestFirstEnabled = nearestFirst
            }
            if let widgetNearest = applicationContext["widgetNearestEnabled"] as? Bool {
                self.widgetNearestEnabled = widgetNearest
            }
            let remoteWidgetStop = applicationContext["widgetStopId"] as? String
            if remoteWidgetStop != self.widgetStopId {
                self.widgetStopId = remoteWidgetStop
            }
        }
    }
}
