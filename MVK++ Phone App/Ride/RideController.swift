//
//  RideController.swift
//  MVK++ Phone App
//
//  The ride's runtime, ported from the effects of the web app's `RideLayer`
//  and `RidePanel`. It lives outside the views so it keeps working while the
//  phone is locked in a pocket: it follows the trip live, closes the ride at
//  the rider's stop, carries a loop journey over to the bus's next trip,
//  asks when the phone has left the bus, drives the Live Activity and the
//  haptics, and runs boarding detection while no ride is on.
//

import Combine
import CoreLocation
import Foundation

enum RideSetupStep: Equatable {
    case from, to, loop
}

@MainActor
final class RideController: ObservableObject {
    static let shared = RideController()

    /// A position counts as fresh for this long (s).
    private static let freshPosS: Double = 60
    /// A ride never closed whose trip has no data is over after this long (s).
    private static let staleRideS: Double = 3 * 3600
    /// After „Még rajta vagyok” the away question waits this long (s).
    private static let awaySnoozeS: Double = 15 * 60
    /// An unclosed ride older than a day whose trip cannot be loaded is dropped (s).
    private static let lostRideS: Double = 24 * 3600
    private static let savedNoteS: Double = 8

    let store: RideStore

    @Published private(set) var trip: TripLive?
    @Published private(set) var cont: Continuation?
    @Published private(set) var traffic: [TrafficAhead] = []
    @Published var step: RideSetupStep?
    @Published var alightPicker = false
    @Published var awayAsk = false
    @Published private(set) var candidate: BoardingCandidate?
    /// The ride just closed; `atLoop`: it ended at a turning loop (going round is still possible).
    @Published private(set) var saved: (ride: Ride, atLoop: Bool)?
    @Published private(set) var looping = false
    /// Answer to the „Felszálltam” shortcut when nothing nearby could be matched.
    @Published var notice: String?

    private weak var location: LocationProvider?
    private weak var transit: TransitStore?
    private var tripFeed: TripLiveFeed?
    private var feedKey = ""
    private let contFeed = ContinuationFeed()
    private let trafficFeed = TrafficFeed()
    private var trafficSegments: [LiveTrafficSegment] = []
    private var awaySnooze: Double = 0
    private var alighting = AlightingDetector()
    private let detector = BoardingDetector()
    private var cancellables: Set<AnyCancellable> = []
    private var savedTimer: Task<Void, Never>?
    private var lastPassed: Int?
    private var hapticDestFor: String?
    private var pendingBoardNearest = false
    private let activity = RideActivityController()

    init(store: RideStore = .shared) {
        self.store = store
    }

    // MARK: - Wiring

    func attach(location: LocationProvider, transit: TransitStore) {
        guard self.location == nil else { return }
        self.location = location
        self.transit = transit
        contFeed.onChange = { [weak self] c in
            self?.cont = c
            self?.evaluate()
        }
        trafficFeed.onChange = { [weak self] segments in
            self?.trafficSegments = segments
            self?.updateTraffic()
        }
        store.$active
            .removeDuplicates()
            .sink { [weak self] active in
                Task { @MainActor in self?.activeChanged(active) }
            }
            .store(in: &cancellables)
        location.$position
            .sink { [weak self] _ in
                Task { @MainActor in self?.positionChanged() }
            }
            .store(in: &cancellables)
        RealtimeClient.shared.$clockVersion
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.dropLostRide()
                    self?.evaluate()
                }
            }
            .store(in: &cancellables)
        RideIntentBridge.alight = { [weak self] in self?.alightNow() }
        RideIntentBridge.boardNearest = { [weak self] in await self?.boardNearest() ?? "" }
        store.syncRides()
        activeChanged(store.active)
    }

    var active: ActiveRide? { store.active }

    private var position: GeoPosition? {
        guard let location, location.status == .watching else { return nil }
        return location.position
    }

    private var serverNow: Double { RealtimeClient.shared.serverNow }
    private var clockReady: Bool { RealtimeClient.shared.clockVersion > 0 }

    private func activeChanged(_ active: ActiveRide?) {
        guard let active else {
            tripFeed?.stop()
            tripFeed = nil
            feedKey = ""
            trip = nil
            contFeed.stop()
            cont = nil
            trafficFeed.stop()
            traffic = []
            step = nil
            alightPicker = false
            awayAsk = false
            lastPassed = nil
            location?.setRideTracking(false)
            activity.end(final: nil)
            detector.startMotion()
            return
        }
        candidate = nil
        detector.reset()
        location?.setRideTracking(true)
        let key = "\(active.id)|\(active.tripId)|\(active.serviceDate)"
        if key != feedKey {
            feedKey = key
            tripFeed?.stop()
            trip = nil
            step = nil
            alightPicker = false
            awayAsk = false
            lastPassed = nil
            let feed = TripLiveFeed(tripId: active.tripId, date: active.serviceDate)
            feed.onChange = { [weak self] value in
                self?.trip = value
                self?.updateTraffic()
                self?.evaluate()
            }
            feed.start()
            tripFeed = feed
        }
        if active.turn != nil {
            contFeed.start(tripId: active.tripId, vehicleId: active.vehicleId)
        } else {
            contFeed.stop()
            cont = nil
        }
        evaluate()
    }

    private func positionChanged() {
        if store.active != nil {
            evaluate()
        } else {
            detect()
        }
    }

    // MARK: - Derived

    var mode: TransitMode {
        guard let a = store.active else { return .bus }
        return TransitIds.rideMode(vehicleId: a.vehicleId, tripId: a.tripId)
    }

    var busPosition: RidePoint? {
        if store.active?.turn != nil {
            return cont?.vehicle.map { RidePoint(lat: $0.lat, lon: $0.lon) }
        }
        return trip?.vehicle.map { RidePoint(lat: $0.lat, lon: $0.lon) }
    }

    var freshPosition: GeoPosition? {
        guard let p = position, Date().timeIntervalSince1970 - p.at <= Self.freshPosS else { return nil }
        return p
    }

    var isAway: Bool {
        guard let fresh = freshPosition, let bus = busPosition else { return false }
        return RideLogic.distM(RidePoint(lat: fresh.lat, lon: fresh.lon), bus) > mode.proximity.away
    }

    var passed: Int { trip?.passed ?? -1 }

    /// Where the bus is now (already the stop if it is standing at it).
    var cur: Int {
        guard let trip else { return 0 }
        return RideLogic.currentStopIdx(trip.stops, passed: passed, at: busPosition, atStopM: mode.proximity.atStop)
    }

    var fromIdx: Int { store.active?.fromIdx ?? 0 }
    var lastIdx: Int { (trip?.stops.count ?? 1) - 1 }

    var needsFrom: Bool {
        guard let a = store.active else { return false }
        return a.fromConfirmed != true || a.fromIdx == nil
    }

    var destPending: Bool {
        guard let a = store.active else { return false }
        return a.destIdx == nil && a.loopPlan == nil && a.destStopId != nil
    }

    var needsDest: Bool {
        guard let a = store.active else { return false }
        return a.destIdx == nil && a.loopPlan == nil && a.destStopId == nil
    }

    var setup: RideSetupStep? {
        if needsFrom { return .from }
        return step ?? (needsDest ? .to : nil)
    }

    var worstTraffic: TrafficAhead? { traffic.max { $0.excessS < $1.excessS } }

    private func updateTraffic() {
        guard let trip, let a = store.active, a.turn == nil else {
            trafficFeed.stop()
            traffic = []
            return
        }
        trafficFeed.start()
        traffic = TrafficFeed.ahead(trafficSegments, stops: trip.stops, from: max(passed, fromIdx), to: a.destIdx ?? lastIdx)
    }

    // MARK: - Effects

    /// The web's RidePanel effects, run whenever the trip, the position, the
    /// continuation or the ride itself changes.
    private func evaluate() {
        guard let a = store.active else { return }
        let turn = a.turn
        let plan = a.loopPlan

        // An old ride turning at the terminus carries on as a loop journey.
        if turn != nil, plan == nil {
            store.patchActive { $0.loopPlan = LoopPlan(stopId: nil, stopName: nil, tripId: nil) }
            return
        }

        guard let trip else {
            activity.update(ride: a, trip: nil, controller: self)
            return
        }

        // Loop journey's next leg: the alighting stop already chosen, on this trip.
        if !trip.stops.isEmpty, destPending {
            var idx = trip.stops.firstIndex { $0.idx > 0 && $0.id == a.destStopId }
            if idx == nil, let name = a.destStopName {
                idx = trip.stops.firstIndex { $0.idx > 0 && $0.name == name }
            }
            store.patchActive { r in
                if let idx, idx > 0 { r.destIdx = idx }
                r.destStopId = nil
                r.destStopName = nil
            }
            return
        }

        haptics(a, trip)

        let times = trip.times
        // The bus reached the chosen stop (or the run closed). A loop journey
        // does not close at the terminus: it carries on with the next trip.
        if let run = trip.run, !needsFrom, turn == nil, setup == nil, !alightPicker {
            let done = run.status != "running" && passed > fromIdx
            if let dest = a.destIdx {
                if passed >= dest || done {
                    finish(at: dest, endedBy: .dest, alightedAt: nil)
                    return
                }
            } else if plan != nil, passed >= lastIdx || done, clockReady {
                let arrivedAt = run.actualEnd ?? times[lastIdx]?.arr ?? serverNow.rounded()
                let name = trip.stops.indices.contains(lastIdx) ? trip.stops[lastIdx].name : "végállomás"
                store.patchActive { $0.turn = RideTurn(arrivedAt: arrivedAt, atIdx: lastIdx, terminusName: name) }
                return
            }
        }

        // Loop journey at the terminus: carries on when the bus leaves, wherever the phone is.
        if let turn, clockReady {
            let now = serverNow.rounded()
            let decision = RideLogic.plannedTurnDecision(arrivedAt: turn.arrivedAt, cont: cont, now: now)
            if decision == .continue, let next = cont?.next {
                chainNext(a, trip, turn: turn, next: next, dest: plan)
                return
            }
            if decision == .alight || (cont == nil && now - turn.arrivedAt > Self.staleRideS) {
                finish(at: turn.atIdx, endedBy: .terminus, alightedAt: turn.arrivedAt)
                return
            }
        }

        // Never closed and the server has no run for its trip: after hours it closes.
        if trip.run == nil, clockReady, serverNow - a.boardedAt >= Self.staleRideS {
            if trip.stops.count < 2 || needsFrom {
                store.cancelRide()
                return
            }
            finish(at: a.destIdx ?? lastIdx, endedBy: .terminus, alightedAt: nil)
            return
        }

        // Far from the bus for long: only ask — the bus GPS can be wrong too.
        let detectorOn = !needsFrom && turn == nil && setup == nil && !alightPicker && Date().timeIntervalSince1970 > awaySnooze
        if alighting.sample(enabled: detectorOn, position: position, vehicle: busPosition), !awayAsk {
            awayAsk = true
            RideHaptics.detected()
            RideNotifier.away(words: mode.words)
        }

        activity.update(ride: a, trip: trip, controller: self)
    }

    private func haptics(_ a: ActiveRide, _ trip: TripLive) {
        let p = trip.passed
        defer { lastPassed = p }
        guard let last = lastPassed, p > last else { return }
        if let dest = a.destIdx, p == dest - 1, hapticDestFor != a.id {
            hapticDestFor = a.id
            RideHaptics.approachingDestination()
            if trip.stops.indices.contains(dest) { RideNotifier.approaching(stop: trip.stops[dest].name) }
        } else {
            RideHaptics.nextStop()
        }
    }

    private func dropLostRide() {
        guard clockReady, let a = store.active, serverNow - a.boardedAt > Self.lostRideS else { return }
        store.cancelRide()
    }

    // MARK: - Closing

    /// The closing fields at a stop. `alightedAt`: when the bus has no
    /// arrival event there yet — nil lets timetable + delay decide.
    func endFields(_ ride: ActiveRide, _ trip: TripLive, at atIdx: Int, endedBy: RideEndedBy?, alightedAt: Double?) -> RideEnd {
        let times = trip.times
        let from = ride.fromIdx ?? 0
        let idx = min(max(atIdx, from), trip.stops.count - 1)
        let near = RideLogic.nearestDelayS(times, idx)
        let to = RideLogic.alightAt(trip.stops, times, idx, .init(at: alightedAt, delayS: alightedAt != nil ? (trip.delayS ?? near) : (near ?? trip.delayS)))
        let board = times[from] != nil ? RideLogic.boardAt(trip.stops, times, from, .init(at: ride.boardedAt, delayS: ride.delayAtBoardS)) : nil
        var end = RideEnd(
            alightedAt: to?.alightedAt ?? alightedAt ?? serverNow.rounded(),
            toStopId: to?.toStopId,
            toStopName: to?.toStopName,
            stops: to != nil ? max(0, idx - from) : nil,
            distanceM: to != nil ? RideLogic.pathLengthM(trip.stops, from: from, to: idx) : nil,
            delayAtAlightS: to?.delayAtAlightS ?? trip.delayS,
            loopEnd: trip.loopEnd,
            endedBy: endedBy
        )
        if let board {
            end.boardedAt = board.boardedAt
            end.delayAtBoardS = .some(board.delayAtBoardS)
        } else if ride.delayAtBoardS == nil {
            end.delayAtBoardS = .some(RideLogic.nearestDelayS(times, from))
        }
        return end
    }

    private func finish(at atIdx: Int, endedBy: RideEndedBy, alightedAt: Double?) {
        guard let a = store.active, let trip else { return }
        let fields = endFields(a, trip, at: atIdx, endedBy: endedBy, alightedAt: alightedAt)
        guard let ride = store.finishRide(fields) else { return }
        RideHaptics.alighted()
        activity.end(final: ride)
        if endedBy != .user { RideNotifier.closed(ride) }
        let atLoop = trip.loopEnd && max(atIdx, a.fromIdx ?? 0) >= trip.stops.count - 1
        showSaved(ride, atLoop: atLoop)
    }

    private func chainNext(_ a: ActiveRide, _ trip: TripLive, turn: RideTurn, next: Continuation.Next, dest: LoopPlan?) {
        store.continueRide(
            endFields(a, trip, at: turn.atIdx, endedBy: nil, alightedAt: turn.arrivedAt),
            next: NextLeg(
                tripId: next.tripId, route: next.route, headsign: next.headsign, color: next.color, text: next.text,
                boardedAt: next.departedAt ?? serverNow.rounded(), fromStopId: next.firstStopId,
                fromStopName: next.firstStopName, delayAtBoardS: next.startDelayS
            ),
            dest: dest
        )
        RideHaptics.nextStop()
    }

    private func showSaved(_ ride: Ride, atLoop: Bool) {
        saved = (ride, atLoop)
        savedTimer?.cancel()
        guard !Self.endedOnItsOwn(ride), !atLoop else { return }
        savedTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.savedNoteS))
            guard !Task.isCancelled else { return }
            self?.saved = nil
        }
    }

    func dismissSaved() {
        savedTimer?.cancel()
        saved = nil
    }

    /// The app closed it on its own (the rider did not mark the stop): ask whether that is right.
    static func endedOnItsOwn(_ r: Ride) -> Bool {
        r.endedBy == .terminus || r.endedBy == .away
    }

    // MARK: - Rider actions

    func pickFrom(_ idx: Int) {
        guard let a = store.active, let trip else { return }
        let times = trip.times
        let fields = RideLogic.boardAt(trip.stops, times, idx, .init(at: idx >= cur ? a.boardedAt : nil, delayS: RideLogic.nearestDelayS(times, idx) ?? trip.delayS))
        let keepDest = a.destIdx.map { $0 > idx } ?? false
        store.patchActive { r in
            r.fromIdx = idx
            if let fields {
                r.fromStopId = fields.fromStopId
                r.fromStopName = fields.fromStopName
                r.boardedAt = fields.boardedAt
                r.delayAtBoardS = fields.delayAtBoardS
            }
            r.fromConfirmed = true
            r.destIdx = keepDest ? a.destIdx : nil
            r.serviceDate = trip.run?.serviceDate ?? a.serviceDate
        }
        step = keepDest || a.loopPlan != nil ? nil : .to
        evaluate()
    }

    func pickDest(_ idx: Int) {
        store.setDestination(idx)
        step = nil
        evaluate()
    }

    func pickLoop(_ plan: LoopPlan) {
        store.patchActive { r in
            r.loopPlan = plan
            r.destIdx = nil
            r.destStopId = nil
            r.destStopName = nil
        }
        step = nil
        evaluate()
    }

    /// „Korábban leszálltam” / „Hol szálltál le?”: one of the stops the bus has passed.
    func pickTo(_ idx: Int) {
        alightPicker = false
        finish(at: idx, endedBy: .user, alightedAt: idx >= cur ? serverNow.rounded() : nil)
    }

    /// „Leszálltam”.
    func alightNow() {
        guard let a = store.active, let trip else { return }
        if let turn = a.turn {
            finish(at: turn.atIdx, endedBy: .user, alightedAt: turn.arrivedAt)
            return
        }
        // The phone is far from the bus already: it got off earlier — ask where.
        if isAway {
            alightPicker = true
            return
        }
        let at = freshPosition.map { RidePoint(lat: $0.lat, lon: $0.lon) } ?? busPosition
        let idx = RideLogic.currentStopIdx(trip.stops, passed: passed, at: at, atStopM: mode.proximity.atStop)
        finish(at: max(idx, fromIdx), endedBy: .user, alightedAt: serverNow.rounded())
    }

    func turnAlight() {
        guard let turn = store.active?.turn else { return }
        finish(at: turn.atIdx, endedBy: .user, alightedAt: turn.arrivedAt)
    }

    func cancel() {
        store.cancelRide()
    }

    func awayAlighted() {
        awayAsk = false
        alightPicker = true
    }

    func awayStillOn() {
        awayAsk = false
        awaySnooze = Date().timeIntervalSince1970 + Self.awaySnoozeS
    }

    /// „Körbeutazok — a buszon maradtam” on the saved note.
    func loopFromSaved(onFollow: @escaping (String, String) -> Void) async -> [Ride]? {
        guard let saved else { return nil }
        looping = true
        let legs = RideStore.journey(of: saved.ride, in: store.rides)
        guard let last = legs.last else { return nil }
        let c = last.vehicleId.isEmpty ? nil : try? await APIClient.shared.continuation(tripId: last.tripId, vehicleId: last.vehicleId)
        looping = false
        dismissSaved()
        if let next = c?.next, next.kind != nil, !next.cancelled {
            let r = store.extendRideLive(legs, next: NextLeg(
                tripId: next.tripId, route: next.route, headsign: next.headsign, color: next.color, text: next.text,
                boardedAt: next.departedAt ?? next.depTs, fromStopId: next.firstStopId, fromStopName: next.firstStopName,
                delayAtBoardS: next.startDelayS
            ))
            if let r { onFollow(r.tripId, r.vehicleId) }
            return nil
        }
        return legs
    }

    // MARK: - Boarding detection

    func answerYes() {
        guard let c = candidate else { return }
        candidate = nil
        RideBoarding.board(vehicle: c.vehicle, detected: .auto, since: c.since)
    }

    func answerNo() {
        guard let c = candidate else { return }
        detector.snooze(c.vehicle.id)
        candidate = nil
    }

    private func detect() {
        guard store.active == nil, let position = position, let transit else { return }
        if pendingBoardNearest {
            pendingBoardNearest = false
            notice = boardNearestNow(position, transit.liveVehicles)
            return
        }
        guard candidate == nil, location?.isStale == false else { return }
        if let found = detector.sample(position, vehicles: transit.liveVehicles) {
            candidate = found
            RideHaptics.detected()
            RideNotifier.boardingDetected(found.vehicle)
        }
    }

    /// The „Felszálltam” shortcut: boards the closest moving-with vehicle at once.
    func boardNearest() async -> String {
        if store.active != nil { return "Már folyamatban van egy utazásod." }
        guard let transit else { return "Nyisd meg az appot, és próbáld újra." }
        if transit.liveVehicles.isEmpty { await transit.refreshLive() }
        guard let position, location?.isStale == false else {
            location?.start()
            pendingBoardNearest = true
            return "Megkeresem a buszt, amin ülsz…"
        }
        let result = boardNearestNow(position, transit.liveVehicles)
        notice = result
        return result
    }

    private func boardNearestNow(_ position: GeoPosition, _ vehicles: [LiveVehicle]) -> String {
        let me = RidePoint(lat: position.lat, lon: position.lon)
        let nowServer = serverNow
        let best = vehicles.compactMap { v -> (LiveVehicle, Double)? in
            guard let lat = v.lat, let lon = v.lon, !v.tripId.isEmpty, v.estimated != true else { return nil }
            let est = LiveMotionEstimator.estimate(v.motion, nowServer: nowServer, shown: nil)?.coordinate
            let d = RideLogic.distM(me, RidePoint(lat: est?.latitude ?? lat, lon: est?.longitude ?? lon))
            let px = v.rideMode.proximity
            return d <= max(px.near, min(px.far, position.accuracyM + px.near)) ? (v, d) : nil
        }.min { $0.1 < $1.1 }
        guard let (vehicle, _) = best else {
            return "Nem látok járművet a közeledben. Nyisd meg a térképet, és válaszd ki, melyikre szálltál fel."
        }
        RideBoarding.board(vehicle: vehicle, detected: .manual)
        return "Felszálltál: \(vehicle.routeShort) \(vehicle.headsign) felé."
    }
}
