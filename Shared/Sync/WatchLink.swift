//
//  WatchLink.swift
//  MVK++ (shared by the Phone and Watch apps; never started in an extension)
//

import Combine
import Foundation
import WatchConnectivity
import WidgetKit

/// The one `WCSession` delegate on each side of the phone–watch pair.
///
/// A session takes a single delegate, and several stores need it (the
/// watchlist, settings, the ride), so every message goes through here. The
/// application context is one dictionary that replaces the previous one on
/// every send, so the outgoing keys are merged here before each update.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    static let shared = WatchLink()

    /// The other app can take a message right now.
    @Published private(set) var isReachable = false
    /// Watch side: the phone's ride (or the one followed locally).
    /// Phone side: the last ride published.
    @Published private(set) var ride: WatchRideSnapshot?
    /// Watch side: the phone's settings.
    @Published private(set) var settings: WatchSettings
    @Published private(set) var lastSyncAt: Date?
    #if os(iOS)
    /// The phone's ride store sets this once it listens for
    /// `.mvkRideCommand`; until then the watch is told to follow on its own.
    var acceptsRideCommands = false
    #endif

    /// Every application context or message that arrives, on the main actor.
    let received = PassthroughSubject<[String: Any], Never>()

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var outgoing: [String: Any] = [:]
    private var lastComplicationRide: (stopsLeft: Int?, ended: Bool)?

    private override init() {
        settings = WatchSharedState.settings
        #if os(watchOS)
        ride = WatchSharedState.ride
        #endif
        super.init()
    }

    func activate() {
        guard let session, session.activationState != .activated, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Merges keys into the outgoing application context and sends it.
    func update(_ values: [String: Any], removing: [String] = []) {
        for (key, value) in values { outgoing[key] = value }
        for key in removing { outgoing[key] = nil }
        flush()
    }

    private func flush() {
        guard let session, session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        try? session.updateApplicationContext(outgoing)
    }

    // MARK: - Phone → watch

    #if os(iOS)
    /// The phone's ride store calls this on every change, and with `nil`
    /// once the ride is gone.
    func publish(ride: WatchRideSnapshot?) {
        guard ride != self.ride else { return }
        self.ride = ride
        guard let data = ride.flatMap({ try? JSONEncoder().encode($0) }) else {
            update([:], removing: [WatchSyncKey.ride])
            lastComplicationRide = nil
            return
        }
        update([WatchSyncKey.ride: data])

        guard let session, session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage([WatchSyncKey.ride: data], replyHandler: nil)
        } else if session.isComplicationEnabled, let ride, complicationWorthy(ride) {
            // The complication budget is small: only the moments a glance
            // at the wrist must be right — start, the stop before getting
            // off, and the end.
            session.transferCurrentComplicationUserInfo([WatchSyncKey.ride: data])
        }
        lastComplicationRide = ride.map { ($0.stopsLeft, $0.ended) }
    }

    private func complicationWorthy(_ ride: WatchRideSnapshot) -> Bool {
        guard let last = lastComplicationRide else { return true }
        if ride.ended != last.ended { return true }
        return ride.stopsLeft != last.stopsLeft && (ride.stopsLeft ?? .max) <= 2
    }

    func publish(settings: WatchSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        self.settings = settings
        update([WatchSyncKey.settings: data])
    }
    #endif

    // MARK: - Watch → phone

    #if os(watchOS)
    /// Asks the phone's ride store to start or end a ride. False when the
    /// phone cannot be reached or did not take it; the watch then follows
    /// the trip itself.
    func send(_ command: WatchRideCommand) async -> Bool {
        guard let session, session.activationState == .activated, session.isReachable else { return false }
        var message: [String: Any] = [:]
        switch command {
        case .start(let request):
            message[WatchSyncKey.action] = WatchSyncAction.startRide.rawValue
            if let request, let data = try? JSONEncoder().encode(request) {
                message[WatchSyncKey.request] = data
            }
        case .end:
            message[WatchSyncKey.action] = WatchSyncAction.endRide.rawValue
        }
        return await withCheckedContinuation { continuation in
            session.sendMessage(message) { reply in
                continuation.resume(returning: reply[WatchSyncKey.accepted] as? Bool ?? false)
            } errorHandler: { _ in
                continuation.resume(returning: false)
            }
        }
    }

    /// The watch's own follow when the phone is out of reach; shown exactly
    /// like a phone ride.
    func setLocalRide(_ ride: WatchRideSnapshot?) {
        apply(ride: ride)
    }
    #endif

    // MARK: - Incoming

    private func handle(_ payload: [String: Any]) {
        lastSyncAt = Date()
        #if os(watchOS)
        if payload.keys.contains(WatchSyncKey.ride) || payload.keys.contains(WatchSyncKey.settings) {
            let data = payload[WatchSyncKey.ride] as? Data
            let incoming = data.flatMap { try? JSONDecoder().decode(WatchRideSnapshot.self, from: $0) }
            // A context without a ride while the watch follows one on its
            // own does not end the local follow.
            if incoming != nil || ride?.source == .phone {
                apply(ride: incoming)
            }
        }
        if let data = payload[WatchSyncKey.settings] as? Data,
           let decoded = try? JSONDecoder().decode(WatchSettings.self, from: data),
           decoded != settings {
            settings = decoded
            WatchSharedState.save(settings: decoded)
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        received.send(payload)
    }

    #if os(watchOS)
    private func apply(ride incoming: WatchRideSnapshot?) {
        guard incoming != ride else { return }
        ride = incoming
        WatchSharedState.save(ride: incoming)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.ride)
    }
    #endif

    #if os(iOS)
    private func handleCommand(_ message: [String: Any]) -> Bool {
        guard acceptsRideCommands, let raw = message[WatchSyncKey.action] as? String, let action = WatchSyncAction(rawValue: raw) else {
            return false
        }
        let command: WatchRideCommand
        switch action {
        case .startRide:
            let request = (message[WatchSyncKey.request] as? Data).flatMap { try? JSONDecoder().decode(WatchRideRequest.self, from: $0) }
            command = .start(request)
        case .endRide:
            command = .end
        }
        NotificationCenter.default.post(name: .mvkRideCommand, object: command)
        return true
    }
    #endif
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            self.flush()
            #if os(watchOS)
            // The phone's latest ride and settings, in case they changed
            // while this app was not running. The watchlist keys are left
            // alone: a stale copy must not undo a change made on the watch.
            var catchUp: [String: Any] = [:]
            catchUp[WatchSyncKey.ride] = context[WatchSyncKey.ride]
            catchUp[WatchSyncKey.settings] = context[WatchSyncKey.settings]
            if !catchUp.isEmpty { self.handle(catchUp) }
            #endif
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.handle(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        #if os(iOS)
        Task { @MainActor in
            replyHandler([WatchSyncKey.accepted: self.handleCommand(message)])
        }
        #else
        replyHandler([:])
        Task { @MainActor in self.handle(message) }
        #endif
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.handle(userInfo) }
    }
}

/// Widget kinds the apps reload by name.
enum WidgetKinds {
    static let nextDeparture = "NextDepartureWidget"
    static let watchedStops = "WatchedStopsWidget"
    static let ride = "RideWidget"
    static let disruptions = "DisruptionsWidget"
    static let nearbyStop = "NearbyStopWidget"
    static let phoneWatchlist = "WatchlistWidget"
}
