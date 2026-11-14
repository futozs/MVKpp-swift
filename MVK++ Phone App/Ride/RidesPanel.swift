//
//  RidesPanel.swift
//  MVK++ Phone App
//
//  „Utazásaim”: the logged rides' summary and list (web `RidesPanel`),
//  with the delay backfill of older rides (`useDelayBackfill`).
//

import SwiftUI

struct RidesPanel: View {
    @ObservedObject private var store = RideStore.shared
    @State private var fleetSize: Int?
    @State private var fixing: RideLayer.FixRequest?
    @State private var adding: AddRequest?
    @State private var loopRoutes: Set<String> = []
    @State private var confirmDelete: [Ride]?

    /// A journey can be extended as a loop for this many days back (the server keeps two weeks of timetable).
    private static let extendDays: Double = 13

    struct AddRequest: Identifiable {
        let legs: [Ride]
        var id: String { legs.isEmpty ? "new" : legs.map(\.id).joined() }
    }

    private var loggedIn: Bool { RideStore.sessionProvider() != nil }

    var body: some View {
        let journeys = RideStore.groupJourneys(store.rides)
        VStack(alignment: .leading, spacing: 16) {
            header
            if store.rides.isEmpty {
                empty
            } else {
                RideStatsView(stats: RideStats(journeys: journeys), fleetSize: fleetSize)
                RideChartFrame(title: "Utazások", hint: "A legutóbbi elöl") {
                    let extendFrom = RealtimeClient.shared.serverNow.rounded() - Self.extendDays * 86_400
                    LazyVStack(spacing: 0) {
                        ForEach(Array(journeys.prefix(200).enumerated()), id: \.element.first?.id) { index, legs in
                            if index > 0 { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
                            if let last = legs.last {
                                let loopable = (last.loopEnd ?? loopRoutes.contains(last.route)) && last.boardedAt >= extendFrom
                                JourneyRow(
                                    legs: legs,
                                    onFix: RideStore.canFix(legs) ? { fixing = RideLayer.FixRequest(legs: legs, initial: .from) } : nil,
                                    onExtend: loopable ? { adding = AddRequest(legs: legs) } : nil,
                                    onDelete: { confirmDelete = legs }
                                )
                            }
                        }
                    }
                }
            }
        }
        .task {
            store.syncRides()
            fleetSize = await Self.loadFleetSize()
            loopRoutes = (try? await APIClient.shared.rideLoopRoutes()) ?? []
        }
        .task(id: store.rides.count) { await backfillDelays() }
        .sheet(item: $fixing) { RideFixSheet(legs: $0.legs, initial: $0.initial) }
        .sheet(item: $adding) { RideAddSheet(continueFrom: $0.legs.isEmpty ? nil : $0.legs) }
        .confirmationDialog(
            (confirmDelete?.count ?? 0) > 1 ? "Törlöd ezt a körbeutazást (minden menetét)?" : "Törlöd ezt az utazást?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Törlés", role: .destructive) {
                for r in confirmDelete ?? [] { store.deleteRide(r.id) }
                confirmDelete = nil
            }
            Button("Mégse", role: .cancel) { confirmDelete = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Utazásaim").font(.system(size: 18, weight: .bold)).tracking(-0.3).foregroundStyle(Theme.foreground)
                HStack(spacing: 6) {
                    Image(systemName: loggedIn ? "icloud" : "icloud.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(loggedIn ? Theme.primary : Theme.mutedForeground)
                    Text(loggedIn
                         ? (store.unsyncedCount > 0 ? "\(store.unsyncedCount) utazás feltöltésre vár" : "Minden utazás a felhőben is megvan")
                         : "Csak ezen az eszközön — jelentkezz be, és minden feltöltődik")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RideButton(title: "Utazás hozzáadása", systemImage: "plus", variant: .outline, size: .small) {
                adding = AddRequest(legs: [])
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            Image(systemName: "map").font(.system(size: 22)).foregroundStyle(Theme.mutedForeground)
            Text("Még nincs rögzített utazásod").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.foreground).padding(.top, 12)
            Text("A térképen kövess egy buszt, és nyomd meg a „Felszálltam” gombot: megadod, hol szálltál fel és hol szállsz le (vagy hogy körbeutazol), a többit az app intézi. Egy korábbi utat a menetrendből is felvehetsz.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private static func loadFleetSize() async -> Int? {
        guard let url = try? APIClient.shared.url(path: "/stats/vehicles"),
              let (data, response) = try? await APIClient.shared.session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["vehicles"] as? [Any]
        else { return nil }
        return list.count
    }

    // MARK: - Delay backfill

    private static let triedKey = "mvk_ride_delay_tried"
    private static let perVisit = 40

    /// Older rides (mostly added afterwards) without a measured delay at
    /// boarding or alighting get it from the trip's measured stops — only the
    /// missing field is filled.
    private func backfillDelays() async {
        let defaults = UserDefaults.standard
        let stored = defaults.data(forKey: Self.triedKey) ?? defaults.string(forKey: Self.triedKey).map { Data($0.utf8) }
        var tried = Set(stored.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
        let todo = store.rides.filter { ($0.delayAtBoardS == nil || $0.delayAtAlightS == nil) && !$0.tripId.isEmpty && ($0.fromStopId != nil || $0.toStopId != nil) }
        let batch = todo.filter { !tried.contains($0.id) }.prefix(Self.perVisit)
        guard !batch.isEmpty else { return }
        var patches: [String: (inout Ride) -> Void] = [:]
        for r in batch {
            let d: TripDetailResponse
            do {
                d = try await APIClient.shared.rideTrip(tripId: r.tripId, date: r.serviceDate)
            } catch APIError.badStatus {
                tried.insert(r.id)
                continue
            } catch {
                if Task.isCancelled { return }
                continue
            }
            tried.insert(r.id)
            guard let stops = d.stops, !stops.isEmpty, let events = d.events, !events.isEmpty else { continue }
            let times = RideLogic.stopTimes(events)
            let idx = RideLogic.rideStopIdx(stops, fromStopId: r.fromStopId, toStopId: r.toStopId)
            var board: Double?
            var alight: Double?
            if r.delayAtBoardS == nil, let from = idx.from { board = times[from]?.delayS ?? RideLogic.nearestDelayS(times, from) }
            if r.delayAtAlightS == nil, let to = idx.to { alight = times[to]?.delayS ?? RideLogic.nearestDelayS(times, to) }
            let loopEnd = r.loopEnd == nil ? d.loopEnd : nil
            guard board != nil || alight != nil || loopEnd != nil else { continue }
            patches[r.id] = { ride in
                if let board { ride.delayAtBoardS = board }
                if let alight { ride.delayAtAlightS = alight }
                if let loopEnd { ride.loopEnd = loopEnd }
            }
        }
        if let data = try? JSONEncoder().encode(Array(tried).suffix(3000)) { defaults.set(String(decoding: data, as: UTF8.self), forKey: Self.triedKey) }
        if !patches.isEmpty { store.patchRides(patches) }
    }
}

/// One journey: one trip, or the legs of a loop journey together.
struct JourneyRow: View {
    let legs: [Ride]
    var onFix: (() -> Void)?
    var onExtend: (() -> Void)?
    let onDelete: () -> Void

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.timeZone = ServiceClock.timeZone
        f.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return f
    }()

    var body: some View {
        if let first = legs.first, let last = legs.last {
            let loop = legs.count > 1
            let mins = last.alightedAt.map { max(1, Int((($0 - first.boardedAt) / 60).rounded())) }
            let stops = legs.contains { $0.stops != nil } ? legs.reduce(0) { $0 + ($1.stops ?? 0) } : nil
            let meters = legs.contains { $0.distanceM != nil } ? legs.reduce(0) { $0 + ($1.distanceM ?? 0) } : nil
            var seen = Set<String>()
            let routes = legs.filter { seen.insert($0.route).inserted }
            let what = loop ? "Körbeutazás" : "Utazás"

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(routes, id: \.route) { r in RouteTile(short: r.route, colorHex: r.color, textHex: r.text) }
                }
                .frame(width: 48, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    if loop {
                        RideEyebrow(text: "Körbeutazás · \(legs.count) menet", systemImage: "repeat", size: 10.5)
                    }
                    pathText(first: first, last: last)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(2)
                    FlowLayout(spacing: 8) {
                        Text("\(Self.day.string(from: Date(timeIntervalSince1970: first.boardedAt))) \(BudapestClock.hm(first.boardedAt))")
                        if !first.vehicleId.isEmpty {
                            Text(TransitIds.displayVehicleId(first.vehicleId)).font(Theme.mono(11.5, weight: .regular))
                                .accessibilityHint(TransitIds.vehicleIdTitle(first.vehicleId))
                        }
                        if let mins { Text("\(mins) perc") }
                        if let stops { Text("\(stops) megálló") }
                        if let meters, meters > 0 { Text("\(RideFormat.oneDecimal(meters / 1000)) km") }
                        delayFacts
                        if legs.allSatisfy({ $0.detected == .later }) {
                            Text("utólag").padding(.horizontal, 4).background(Theme.muted, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    if let onExtend { action("repeat", label: "\(what): a végállomáson a buszon maradtam — körbeutazás hozzáadása", run: onExtend) }
                    if let onFix { action("pencil", label: "\(what): hol szálltál fel és le", run: onFix) }
                    action("trash", label: "\(what) törlése", run: onDelete)
                }
            }
            .padding(.vertical, 10)
        }
    }

    private func pathText(first: Ride, last: Ride) -> Text {
        var text = Text(first.fromStopName ?? "?")
        for r in legs.dropLast() {
            text = text + Text(" → ").foregroundColor(Theme.mutedForeground) + Text(r.toStopName ?? "?")
        }
        return text + Text(" → ").foregroundColor(Theme.mutedForeground) + Text(last.toStopName ?? "?")
    }

    @ViewBuilder
    private var delayFacts: some View {
        let d = JourneyDelay(legs)
        if d.boardS == nil, d.alightS == nil {
            Text("késés: nincs mérés").foregroundStyle(Theme.mutedForeground.opacity(0.8))
        } else {
            Text(RideFormat.delayLabel(d.boardS ?? d.alightS))
                .font(Theme.mono(11.5, weight: .semibold))
                .foregroundStyle(RideFormat.delayTone(d.boardS ?? d.alightS))
                .accessibilityHint("A busz késése felszálláskor")
            if let extra = d.extraS, extra >= 60 {
                Text("+\(Int((extra / 60).rounded())) perc út közben")
                    .font(Theme.mono(11.5, weight: .regular))
                    .foregroundStyle(Theme.late)
                    .accessibilityHint("Ennyivel tovább tartott az út a menetrendnél")
            }
        }
    }

    private func action(_ systemImage: String, label: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(label)
    }
}
