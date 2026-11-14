//
//  RideStore.swift
//  MVK++ Phone App
//
//  Port of the web app's `lib/rides.ts`: rides started with „Felszálltam”, by
//  the boarding detector, or added afterwards from the timetable. Signed out
//  they stay on the device; signed in every ride is uploaded to `/v3/rides`
//  and the other devices' rides come down.
//
//  Storage keys and JSON match the web's localStorage exactly. Like on the
//  web they are device-only for `/v3/sync`; rides travel through `/v3/rides`:
//   · `mvk_rides`        — [Ride & { synced?: boolean }], newest first, ≤ 5000
//   · `mvk_ride_active`  — ActiveRide | null
//   · `mvk_ride_deleted` — [String], deletions the server has not confirmed
//

import Combine
import Foundation

@MainActor
final class RideStore: ObservableObject {
    static let shared = RideStore()

    static let ridesKey = "mvk_rides"
    static let activeKey = "mvk_ride_active"
    static let deletedKey = "mvk_ride_deleted"
    private static let maxLocal = 5000
    private static let batch = 200

    /// The signed-in account's session token (Keychain).
    static var sessionProvider: @MainActor () -> String? = { AccountSession.current?.sessionToken }

    @Published private(set) var rides: [Ride]
    @Published private(set) var active: ActiveRide?

    private var deleted: [String]
    private let defaults: UserDefaults
    private var syncing: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rides = Self.read([LossyRide].self, Self.ridesKey, defaults)?.compactMap(\.ride) ?? []
        active = Self.read(ActiveRide.self, Self.activeKey, defaults)
        deleted = Self.read([String].self, Self.deletedKey, defaults) ?? []
        // Signing in syncs at once; signing out drops the account's uploaded
        // rides (they stay in the cloud), keeping the ones not yet uploaded.
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .mvkSessionChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncRides() }
            },
            center.addObserver(forName: .mvkRidesReset, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resetAfterSignOut() }
            },
        ]
    }

    private static func read<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) ?? defaults.string(forKey: key).map({ Data($0.utf8) }) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ key: String, _ value: T?) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private func setRides(_ next: [Ride]) {
        rides = Array(next.prefix(Self.maxLocal))
        write(Self.ridesKey, rides)
    }

    private func setActive(_ next: ActiveRide?) {
        active = next
        write(Self.activeKey, next)
    }

    private func setDeleted(_ next: [String]) {
        deleted = Array(next.suffix(1000))
        write(Self.deletedKey, deleted.isEmpty ? nil : deleted)
    }

    // MARK: - Active ride

    @discardableResult
    func startRide(_ ride: ActiveRide) -> ActiveRide {
        setActive(ride)
        return ride
    }

    /// Where to get off on this trip (instead of a planned loop journey).
    func setDestination(_ idx: Int) {
        guard var a = active else { return }
        a.destIdx = idx
        a.destStopId = nil
        a.destStopName = nil
        a.loopPlan = nil
        setActive(a)
    }

    func patchActive(_ change: (inout ActiveRide) -> Void) {
        guard var a = active else { return }
        change(&a)
        setActive(a)
    }

    private func closedRide(_ a: ActiveRide, _ end: RideEnd, chainId: String?) -> Ride {
        var r = Ride(
            id: a.id, serviceDate: a.serviceDate, vehicleId: a.vehicleId, tripId: a.tripId, route: a.route,
            headsign: a.headsign, color: a.color, text: a.text, boardedAt: end.boardedAt ?? a.boardedAt,
            alightedAt: end.alightedAt, fromStopId: a.fromStopId, fromStopName: a.fromStopName,
            toStopId: end.toStopId, toStopName: end.toStopName, stops: end.stops, distanceM: end.distanceM,
            delayAtBoardS: a.delayAtBoardS, delayAtAlightS: end.delayAtAlightS, detected: a.detected,
            chainId: chainId, endedBy: end.endedBy, loopEnd: end.loopEnd, synced: false
        )
        if let d = end.delayAtBoardS { r.delayAtBoardS = d }
        return r
    }

    /// End of the ride: to the front of the log, uploaded when signed in.
    @discardableResult
    func finishRide(_ end: RideEnd) -> Ride? {
        guard let a = active else { return nil }
        let ride = closedRide(a, end, chainId: a.chainId)
        setActive(nil)
        setRides([ride] + rides.filter { $0.id != ride.id })
        syncRides()
        return ride
    }

    private func nextLegRide(_ next: NextLeg, serviceDate: String, vehicleId: String, detected: RideSource, chainId: String, leg: Int, dest: LoopPlan?) -> ActiveRide {
        ActiveRide(
            id: UUID().uuidString.lowercased(), serviceDate: serviceDate, vehicleId: vehicleId, tripId: next.tripId,
            route: next.route, headsign: next.headsign, color: next.color, text: next.text, boardedAt: next.boardedAt,
            fromIdx: 0, fromConfirmed: true, withBus: nil, fromStopId: next.fromStopId, fromStopName: next.fromStopName,
            delayAtBoardS: next.delayAtBoardS, destIdx: nil, destStopId: dest?.stopId, destStopName: dest?.stopName,
            loopPlan: nil, detected: detected, chainId: chainId, leg: leg, turn: nil
        )
    }

    /// Loop journey: the finished trip goes into the log and the next trip on
    /// the same bus starts, linked by the shared `chainId`.
    @discardableResult
    func continueRide(_ end: RideEnd, next: NextLeg, dest: LoopPlan?) -> ActiveRide? {
        guard let a = active else { return nil }
        let chainId = a.chainId ?? a.id
        let done = closedRide(a, end, chainId: chainId)
        let ride = nextLegRide(next, serviceDate: a.serviceDate, vehicleId: a.vehicleId, detected: a.detected, chainId: chainId, leg: (a.leg ?? 1) + 1, dest: dest)
        setRides([done] + rides.filter { $0.id != done.id })
        setActive(ride)
        syncRides()
        return ride
    }

    /// „Körbeutazok” on a ride already closed at the terminus: it carries on
    /// live with the bus's next trip.
    @discardableResult
    func extendRideLive(_ legs: [Ride], next: NextLeg) -> ActiveRide? {
        guard active == nil, let last = legs.last else { return nil }
        let chainId = last.chainId ?? last.id
        let ride = nextLegRide(next, serviceDate: last.serviceDate, vehicleId: last.vehicleId, detected: last.detected == .auto ? .auto : .manual, chainId: chainId, leg: legs.count + 1, dest: nil)
        setActive(ride)
        return ride
    }

    /// Afterwards additions (loop extension, delay backfill): not a fix, so a
    /// corrected ride takes them too — `patchedAt` tells the server.
    func patchRides(_ patches: [String: (inout Ride) -> Void]) {
        guard rides.contains(where: { patches[$0.id] != nil }) else { return }
        let patchedAt = Date().timeIntervalSince1970.rounded()
        setRides(rides.map { r in
            guard let patch = patches[r.id] else { return r }
            var next = r
            patch(&next)
            next.patchedAt = patchedAt
            next.synced = false
            return next
        }.sorted { $0.boardedAt > $1.boardedAt })
        syncRides()
    }

    static func canFix(_ legs: [Ride]) -> Bool {
        !legs.isEmpty && legs.allSatisfy { $0.editedAt == nil }
    }

    /// Afterwards correction of where the rider got on and off; a loop
    /// journey is fixed as a whole.
    @discardableResult
    func fixRide(legIds: [String], fixes: [String: RideFix]) -> Bool {
        let ids = Set(legIds)
        guard Self.canFix(rides.filter { ids.contains($0.id) }) else { return false }
        let editedAt = Date().timeIntervalSince1970.rounded()
        setRides(rides.map { r in
            guard ids.contains(r.id) else { return r }
            var next = r
            fixes[r.id]?.apply(to: &next)
            next.editedAt = editedAt
            next.synced = false
            return next
        }.sorted { $0.boardedAt > $1.boardedAt })
        syncRides()
        return true
    }

    /// Rides added afterwards from the timetable (all legs of a loop journey).
    func addRides(_ legs: [Ride]) {
        guard !legs.isEmpty else { return }
        let ids = Set(legs.map(\.id))
        let fresh = legs.map { r -> Ride in
            var next = r
            next.synced = false
            return next
        }
        setRides((fresh + rides.filter { !ids.contains($0.id) }).sorted { $0.boardedAt > $1.boardedAt })
        syncRides()
    }

    /// Not on it after all (a wrong detection): gone without a trace.
    func cancelRide() {
        setActive(nil)
    }

    func deleteRide(_ id: String) {
        let wasSynced = rides.contains { $0.id == id && $0.synced == true }
        setRides(rides.filter { $0.id != id })
        guard wasSynced || Self.sessionProvider() != nil else { return }
        setDeleted(deleted.filter { $0 != id } + [id])
        Task { await flushDeletes() }
    }

    // MARK: - Journeys

    /// A journey's legs in order (all of a loop journey).
    static func journey(of ride: Ride, in all: [Ride]) -> [Ride] {
        let key = ride.chainId ?? (all.contains { $0.chainId == ride.id } ? ride.id : nil)
        guard let key else { return [ride] }
        return all.filter { $0.chainId == key || $0.id == key }.sorted { $0.boardedAt < $1.boardedAt }
    }

    /// Rides grouped into journeys (a loop journey's legs count as one), newest first.
    static func groupJourneys(_ all: [Ride]) -> [[Ride]] {
        let heads = Set(all.compactMap(\.chainId))
        var chainIndex: [String: Int] = [:]
        var out: [[Ride]] = []
        for r in all {
            guard let key = r.chainId ?? (heads.contains(r.id) ? r.id : nil) else {
                out.append([r])
                continue
            }
            if let i = chainIndex[key] {
                out[i].append(r)
            } else {
                chainIndex[key] = out.count
                out.append([r])
            }
        }
        for (_, i) in chainIndex { out[i].sort { $0.boardedAt < $1.boardedAt } }
        return out
    }

    var unsyncedCount: Int { rides.filter { $0.synced != true }.count }

    // MARK: - Cloud sync

    /// Uploads what is not yet uploaded and downloads the other devices' rides.
    func syncRides() {
        guard syncing == nil else { return }
        syncing = Task { [weak self] in
            await self?.doSync()
            self?.syncing = nil
        }
    }

    /// Signed out: the account's uploaded rides leave this device (they stay
    /// in the cloud); the not-yet-uploaded ones stay so nothing is lost.
    func resetAfterSignOut() {
        setDeleted([])
        setActive(nil)
        setRides(rides.filter { $0.synced != true })
    }

    private func flushDeletes() async {
        guard let session = Self.sessionProvider() else { return }
        for id in deleted {
            do {
                try await APIClient.shared.deleteRide(id: id, session: session)
            } catch {
                return
            }
            setDeleted(deleted.filter { $0 != id })
        }
    }

    private func doSync() async {
        guard let session = Self.sessionProvider() else { return }
        let pending = rides.filter { $0.synced != true }
        var saved = Set<String>()
        var start = 0
        while start < pending.count {
            let chunk = Array(pending[start..<min(start + Self.batch, pending.count)])
            guard let ids = try? await APIClient.shared.uploadRides(chunk, session: session) else { return }
            saved.formUnion(ids)
            start += Self.batch
        }
        await flushDeletes()
        guard let remote = try? await APIClient.shared.downloadRides(session: session) else { return }
        let gone = Set(deleted)
        let remoteIds = Set(remote.map(\.id))
        let complete = remote.count < 5000
        var byId: [String: Ride] = [:]
        var order: [String] = []
        for r in rides {
            let synced = r.synced == true || saved.contains(r.id)
            if synced, complete, !remoteIds.contains(r.id), !saved.contains(r.id) { continue }
            var next = r
            if synced { next.synced = true }
            if byId[r.id] == nil { order.append(r.id) }
            byId[r.id] = next
        }
        for r in remote where !gone.contains(r.id) {
            var next = r
            next.synced = true
            if byId[r.id] == nil { order.append(r.id) }
            byId[r.id] = next
        }
        setRides(order.compactMap { byId[$0] }.sorted { $0.boardedAt > $1.boardedAt })
    }
}
