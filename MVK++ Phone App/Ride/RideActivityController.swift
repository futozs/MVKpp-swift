//
//  RideActivityController.swift
//  MVK++ Phone App
//

import ActivityKit
import Foundation
import UIKit
import UserNotifications

/// Starts, updates and ends the ride's Live Activity from local state —
/// only when something the rider sees has changed.
@MainActor
final class RideActivityController {
    private var activity: Activity<RideActivityAttributes>?
    private var rideId: String?
    private var lastState: RideActivityAttributes.ContentState?

    func update(ride: ActiveRide, trip: TripLive?, controller: RideController) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = Self.state(ride: ride, trip: trip, controller: controller)
        if rideId != ride.id || activity == nil {
            startActivity(ride: ride, state: state)
            return
        }
        guard state != lastState, let activity else { return }
        lastState = state
        var stamped = state
        stamped.updatedAt = Date().timeIntervalSince1970.rounded()
        Task {
            await activity.update(ActivityContent(state: stamped, staleDate: Date().addingTimeInterval(5 * 60)))
        }
    }

    func end(final ride: Ride?) {
        guard let activity else { return }
        self.activity = nil
        rideId = nil
        var state = lastState ?? RideActivityAttributes.ContentState(tripId: ride?.tripId ?? "", live: false, ended: true, updatedAt: 0)
        state.ended = true
        state.live = false
        state.updatedAt = Date().timeIntervalSince1970.rounded()
        if let ride {
            state.phase = .riding
            state.nextStopId = nil
            state.nextStopName = nil
            state.nextStopEtaUnix = nil
            state.destName = ride.toStopName
            state.stopEtaUnix = ride.alightedAt
            state.stopsLeft = 0
            state.progress = 1
        }
        lastState = nil
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: ride == nil ? .immediate : .after(Date().addingTimeInterval(10 * 60)))
        }
    }

    private func startActivity(ride: ActiveRide, state: RideActivityAttributes.ContentState) {
        for stale in Activity<RideActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        let mode = TransitIds.rideMode(vehicleId: ride.vehicleId, tripId: ride.tripId)
        let attributes = RideActivityAttributes(
            route: ride.route,
            color: ride.color,
            text: ride.text,
            headsign: ride.headsign,
            vehicleLabel: TransitIds.displayVehicleId(ride.vehicleId),
            vehicleNoun: mode.noun
        )
        do {
            var stamped = state
            stamped.updatedAt = Date().timeIntervalSince1970.rounded()
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: stamped, staleDate: nil))
            rideId = ride.id
            lastState = state
        } catch {
            activity = nil
            rideId = nil
        }
    }

    static func state(ride: ActiveRide, trip: TripLive?, controller: RideController) -> RideActivityAttributes.ContentState {
        var state = RideActivityAttributes.ContentState(
            tripId: ride.tripId,
            vehicleId: ride.vehicleId,
            live: trip?.vehicle != nil,
            progress: 0,
            ended: false,
            updatedAt: 0,
            phase: .setup,
            leg: ride.leg ?? 1
        )
        guard let trip, !trip.stops.isEmpty else { return state }
        let delay = trip.delayS
        state.delaySec = delay.map { Int($0.rounded()) }
        state.speedKmh = trip.vehicle?.speed.map { Int(($0 * 3.6).rounded()) }
        if let turn = ride.turn {
            state.phase = .turn
            state.turnName = turn.terminusName
            state.progress = 1
            state.destName = ride.loopPlan?.stopName
            return state
        }
        state.phase = controller.setup == nil ? .riding : .setup
        let passed = trip.passed
        let expected = { (idx: Int) -> Double in
            trip.stops[idx].schedTs + (trip.forecast[idx]?.delayS ?? delay ?? 0)
        }
        let nextIdx = passed + 1
        if trip.stops.indices.contains(nextIdx) {
            state.nextStopId = trip.stops[nextIdx].id
            state.nextStopName = trip.stops[nextIdx].name
            state.nextStopEtaUnix = expected(nextIdx).rounded()
        }
        let from = ride.fromIdx ?? 0
        let end = ride.destIdx ?? (trip.stops.count - 1)
        if let dest = ride.destIdx, trip.stops.indices.contains(dest) {
            state.destName = trip.stops[dest].name
            state.stopEtaUnix = expected(dest).rounded()
            state.stopsLeft = max(0, dest - passed)
        } else if ride.loopPlan != nil {
            state.turnName = trip.stops.last?.name
            state.destName = ride.loopPlan?.stopName
        }
        let span = max(1, end - from)
        state.progress = min(1, max(0, Double(passed - from) / Double(span)))
        return state
    }
}

/// Local notifications for ride moments that matter while the phone is in
/// a pocket. In the foreground the panel and the haptics say it instead.
@MainActor
enum RideNotifier {
    private static func post(_ id: String, title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ride-\(id)", content: content, trigger: nil))
    }

    static func approaching(stop: String) {
        post("approach", title: "Következik: \(stop)", body: "A következő megállóban szállsz le.")
    }

    static func away(words: TransitMode.Words) {
        post("away", title: "Már nem vagy a \(words.on)?", body: "Percek óta messze vagy tőle. Amíg nem válaszolsz, az utazás megy tovább a kijelölt leszállóhelyig.")
    }

    static func closed(_ ride: Ride) {
        post("closed", title: "Utazás elmentve", body: "\(ride.fromStopName ?? "?") → \(ride.toStopName ?? "?")")
    }

    static func boardingDetected(_ v: LiveVehicle) {
        let w = v.rideMode.words
        post("detected", title: "Együtt mozogsz egy \(w.val)", body: "Éppen erre a \(w.ra) szálltál fel? \(v.routeShort) · \(v.headsign)")
    }
}
