//
//  RideController.swift
//  MVK++ Watch App
//

import Combine
import Foundation
import UserNotifications
import WatchKit

/// "Felszálltam" on the wrist.
///
/// The phone's ride store is the owner: a start goes to it first, and its
/// snapshots come back through `WatchLink`. When the phone cannot be reached
/// the watch follows the run itself from the trip-progress feed and builds
/// the same snapshot, so the ride screen and the complications never care
/// which device is counting the stops.
///
/// Either way the wrist taps on every stop passed and insists on the one
/// before getting off.
@MainActor
final class RideController: ObservableObject {
    static let shared = RideController()

    @Published private(set) var isStarting = false
    /// One line under the ride, e.g. why the watch is following on its own.
    @Published private(set) var note: String?
    /// The phone took the start and its first snapshot is on the way.
    @Published private(set) var awaitingPhone = false

    private var localTask: Task<Void, Never>?
    private var localRequest: WatchRideRequest?
    private var cancellable: AnyCancellable?
    private var lastRide: WatchRideSnapshot?

    private static let pollInterval: Duration = .seconds(10)
    private static let maxLocalRide: TimeInterval = 3 * 60 * 60
    private static let hapticsKey = "mvk_watch_haptics"

    var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.hapticsKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.hapticsKey)
        }
    }

    private init() {
        lastRide = WatchLink.shared.ride
        cancellable = WatchLink.shared.$ride
            .removeDuplicates()
            .sink { [weak self] ride in self?.react(to: ride) }
        if let ride = WatchLink.shared.ride, ride.source == .watch, !ride.ended {
            // A follow the app was closed on hours ago is over, whatever the
            // feed would say about that run now.
            if Date().timeIntervalSince1970 - ride.boardedAt > Self.maxLocalRide {
                WatchLink.shared.setLocalRide(nil)
            } else {
                resume(ride)
            }
        }
    }

    // MARK: - Commands

    func board(_ request: WatchRideRequest) async {
        isStarting = true
        defer { isStarting = false }
        note = nil
        if await WatchLink.shared.send(.start(request)) {
            note = "A telefon követi az utat."
            awaitingPhone = WatchLink.shared.ride == nil
            return
        }
        note = "A telefon nem elérhető, az óra követi az utat."
        startLocal(request)
    }

    func end() async {
        guard let ride = WatchLink.shared.ride else { return }
        if ride.source == .phone, !ride.ended, await WatchLink.shared.send(.end) {
            return
        }
        stopLocal()
        WatchLink.shared.setLocalRide(nil)
        note = nil
    }

    /// Clears an ended ride from the screen and the complications.
    func dismissEnded() {
        guard WatchLink.shared.ride?.ended == true else { return }
        stopLocal()
        WatchLink.shared.setLocalRide(nil)
    }

    // MARK: - Local follow

    private func startLocal(_ request: WatchRideRequest) {
        let now = Date().timeIntervalSince1970
        let ride = WatchRideSnapshot(
            rideId: UUID().uuidString.lowercased(),
            tripId: request.tripId,
            vehicleId: request.vehicleId,
            route: request.route,
            color: request.color,
            textColor: request.textColor,
            headsign: request.headsign,
            mode: nil,
            boardedStopId: request.boardStopId,
            boardedStopName: request.boardStopName,
            destinationStopId: request.destinationStopId,
            destinationStopName: request.destinationStopName,
            nextStopId: nil,
            nextStopName: nil,
            nextStopAt: nil,
            stopsLeft: nil,
            delaySec: nil,
            progress: 0,
            boardedAt: now,
            updatedAt: now,
            ended: false,
            source: .watch
        )
        WatchLink.shared.setLocalRide(ride)
        resume(ride)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func resume(_ ride: WatchRideSnapshot) {
        localRequest = WatchRideRequest(
            tripId: ride.tripId,
            vehicleId: ride.vehicleId,
            route: ride.route,
            color: ride.color,
            textColor: ride.textColor,
            headsign: ride.headsign,
            boardStopId: ride.boardedStopId,
            boardStopName: ride.boardedStopName,
            destinationStopId: ride.destinationStopId,
            destinationStopName: ride.destinationStopName
        )
        localTask?.cancel()
        localTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func stopLocal() {
        localTask?.cancel()
        localTask = nil
        localRequest = nil
    }

    private func tick() async {
        guard let request = localRequest, let current = WatchLink.shared.ride, current.source == .watch else {
            stopLocal()
            return
        }
        guard let progress = try? await APIClient.shared.tripProgress(tripId: request.tripId, vehicleId: request.vehicleId) else {
            return
        }
        let next = Self.snapshot(from: progress, request: request, previous: current)
        WatchLink.shared.setLocalRide(next)
        if next.ended { stopLocal() }
    }

    /// The rider's leg on the run: boarding stop → destination (or the
    /// terminus), with the vehicle's next stop placed on it.
    static func snapshot(from progress: TripProgressResponse, request: WatchRideRequest, previous: WatchRideSnapshot) -> WatchRideSnapshot {
        let stops = progress.stops
        var ride = previous
        ride.updatedAt = Date().timeIntervalSince1970
        ride.vehicleId = progress.vehicle?.id ?? previous.vehicleId
        ride.delaySec = progress.scheduleDeviationSec ?? previous.delaySec
        guard !stops.isEmpty else { return ride }

        let lastIndex = stops.count - 1
        let destIndex = request.destinationStopId.flatMap { id in stops.firstIndex { $0.id == id } } ?? lastIndex
        let nextIndex = progress.nextStop.flatMap { next in stops.firstIndex { $0.id == next.id } }
            ?? progress.segmentIndex.map { min($0 + 1, lastIndex) }
        let boardIndex = request.boardStopId.flatMap { id in stops.firstIndex { $0.id == id } }
            ?? previous.boardedStopId.flatMap { id in stops.firstIndex { $0.id == id } }
            ?? max(0, (nextIndex ?? 1) - 1)

        if ride.boardedStopId == nil {
            ride.boardedStopId = stops[boardIndex].id
            ride.boardedStopName = stops[boardIndex].name
        }
        ride.destinationStopId = stops[destIndex].id
        ride.destinationStopName = stops[destIndex].name

        guard let nextIndex else {
            let finished = (progress.progress ?? 0) >= 0.99
            ride.ended = finished
            if finished { ride.progress = 1; ride.stopsLeft = 0 }
            return ride
        }

        if nextIndex > destIndex {
            ride.ended = true
            ride.stopsLeft = 0
            ride.progress = 1
            ride.nextStopId = nil
            ride.nextStopName = nil
            ride.nextStopAt = nil
            return ride
        }

        let next = stops[nextIndex]
        ride.nextStopId = next.id
        ride.nextStopName = next.name
        ride.nextStopAt = due(secondsOfServiceDay: next.dep + (ride.delaySec ?? 0)).timeIntervalSince1970
        ride.stopsLeft = destIndex - nextIndex + 1
        let span = Double(max(1, destIndex - boardIndex))
        let travelled = Double(nextIndex - 1 - boardIndex) + (progress.segmentFraction ?? 0)
        ride.progress = min(1, max(0, travelled / span))
        return ride
    }

    /// GTFS times count from midnight of the run's service day in Budapest
    /// and go past 24:00 for the night's last trips, so a 26:50 run is still
    /// yesterday's after 03:00 rolls the day over. Of today's and
    /// yesterday's reading, the one nearer to now is the run's.
    private static func due(secondsOfServiceDay seconds: Int, now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return [today, yesterday]
            .map { $0.addingTimeInterval(Double(seconds)) }
            .min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) } ?? today
    }

    // MARK: - Haptics

    private func react(to ride: WatchRideSnapshot?) {
        defer { lastRide = ride }
        if ride != nil { awaitingPhone = false }
        guard let ride, hapticsEnabled else { return }
        let previous = lastRide?.rideId == ride.rideId ? lastRide : nil

        if ride.ended {
            if previous?.ended == false {
                WKInterfaceDevice.current().play(.success)
                notify(title: "Megérkeztél", body: ride.destinationStopName.map { "\($0) · \(ride.route)" } ?? ride.route)
            }
            return
        }
        guard let previous else {
            WKInterfaceDevice.current().play(.start)
            return
        }
        if ride.isGetOffNext, !previous.isGetOffNext {
            WKInterfaceDevice.current().play(.notification)
            notify(title: "Következő megálló: \(ride.nextStopName ?? "")", body: "Itt szállsz le — készülj.")
        } else if ride.nextStopId != previous.nextStopId, ride.nextStopId != nil {
            WKInterfaceDevice.current().play(.click)
        }
    }

    /// Reaches the rider even with the wrist down, when the app is not on
    /// screen to tap.
    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "mvk-ride", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
