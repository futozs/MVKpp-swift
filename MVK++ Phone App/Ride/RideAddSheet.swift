//
//  RideAddSheet.swift
//  MVK++ Phone App
//
//  A ride added afterwards from the timetable: day → route → departure →
//  where on and off. On a loop journey „A buszon maradtam” at the terminus
//  leads to the next trip. `continueFrom`: an existing journey extended as a
//  loop journey (and its last leg stretched to the terminus if it closed early).
//

import SwiftUI

struct RideAddSheet: View {
    var continueFrom: [Ride]?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = RideStore.shared

    private enum Step { case pick, trips, leg, next }

    private struct Detail: Equatable {
        let stops: [TripStop]
        let times: [Int: RideStopTime]
        let loopEnd: Bool
    }

    private struct LegDraft: Equatable {
        let trip: PastTripRow
        var vehicleId: String
        var vehicleKnown: Bool
        var fixedFrom: Bool
        var from: Int?
        var to: Int?
        var done: Ride?
    }

    @State private var days: [(iso: String, label: String)] = RideAddSheet.recentDays()
    @State private var day = ""
    @State private var route: PastRoute?
    @State private var step: Step = .pick
    @State private var legs: [LegDraft] = []
    @State private var mode: RideFixSheet.Mode = .from
    @State private var detail: Detail?
    @State private var detailFailed = false
    @State private var baseDetail: Detail?

    private static let futureSlackS: Double = 120
    private static let favoritesCount = 5
    private static let daysBack = 7

    private var base: Ride? { continueFrom?.last }
    private var current: LegDraft? { step == .leg ? legs.last : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                switch step {
                case .pick:
                    RideDayRoutePicker(days: days, day: $day, favorites: favorites) { r in
                        route = r
                        step = .trips
                    }
                case .trips:
                    if let route {
                        RideTripPicker(date: day, today: day == days.first?.iso, route: route.short) { startLeg($0, continued: false) }
                    }
                case .next:
                    if let nextOf {
                        RideNextPicker(date: nextOf.date, trip: nextOf.trip, vehicle: prevVehicle) { startLeg($0, continued: true) }
                    }
                case .leg:
                    if let current { legStops(current) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            if let current, step == .leg { footer(current) }
        }
        .background(Theme.card)
        .presentationDetents([.fraction(0.85)])
        .presentationBackground(Theme.card)
        .onAppear {
            if day.isEmpty { day = days.first?.iso ?? "" }
            if base != nil, legs.isEmpty { step = .next }
        }
        .task(id: base?.id) { await loadBase() }
        .task(id: current.map { "\($0.trip.serviceDate)|\($0.trip.tripId)" }) { await loadDetail() }
    }

    // MARK: - Header

    private var title: String {
        switch step {
        case .pick, .trips: return "Utazás hozzáadása"
        case .next: return base != nil && legs.isEmpty ? "Körbeutazás hozzáadása" : "Hogyan ment tovább a busz?"
        case .leg: return current?.fixedFrom == true ? "Hol szálltál le?" : "Hol szálltál fel és le?"
        }
    }

    private var description: String {
        switch step {
        case .pick: return "Válaszd ki a menetrendből, melyik járattal utaztál."
        case .trips: return "\(days.first { $0.iso == day }?.label ?? day) · melyik indulással mentél?"
        case .next:
            let terminus = nextOf?.terminus ?? ""
            let extra = baseFix != nil && legs.isEmpty ? " Az előző menet (\(base?.toStopName ?? "?") helyett) a végállomásig hosszabbodik." : ""
            return "A végállomáson (\(terminus.isEmpty ? "?" : terminus)) a buszon maradtál — melyik menettel ment tovább?\(extra)"
        case .leg:
            guard let current else { return "" }
            let legNo = (continueFrom?.count ?? 0) + legs.count
            return "\(current.trip.headsign) · \(BudapestClock.hm(current.trip.depTs))\(legNo > 1 ? " · \(legNo). menet" : "")"
        }
    }

    private var canGoBack: Bool { step != .pick && !(step == .next && legs.isEmpty) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if canGoBack {
                    Button(action: back) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Vissza")
                    .padding(.leading, -6)
                }
                if step == .trips, let route {
                    RouteTile(short: route.short, colorHex: route.color, textHex: route.text, size: .small)
                }
                if step == .leg, let current {
                    RouteTile(short: current.trip.route, colorHex: current.trip.color, textHex: current.trip.text, size: .small)
                }
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.foreground)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bezárás")
            }
            Text(description)
                .font(.system(size: 14))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Data

    /// Most ridden first; a tie keeps the order the routes first appear in
    /// (the web's `Map` insertion order with a stable sort).
    private var favorites: [String] {
        var n: [String: Int] = [:]
        var order: [String] = []
        for r in store.rides {
            if n[r.route] == nil { order.append(r.route) }
            n[r.route, default: 0] += 1
        }
        let ranked = order.enumerated().sorted { a, b in
            let na = n[a.element] ?? 0, nb = n[b.element] ?? 0
            return na != nb ? na > nb : a.offset < b.offset
        }
        return ranked.prefix(Self.favoritesCount).map(\.element)
    }

    private var prevVehicle: String { legs.last?.vehicleId ?? base?.vehicleId ?? "" }

    private var nextOf: (date: String, trip: String, terminus: String)? {
        if let prev = legs.last { return (prev.trip.serviceDate, prev.trip.tripId, prev.trip.destinationName) }
        if let base {
            let terminus = baseDetail?.stops.last?.name ?? base.toStopName ?? ""
            return (base.serviceDate, base.tripId, terminus)
        }
        return nil
    }

    /// The extended journey's last leg, stretched to the terminus when it closed earlier.
    private var baseFix: ((inout Ride) -> Void)? {
        guard let base, let d = baseDetail else { return nil }
        let last = d.stops.count - 1
        guard last >= 1, d.stops[last].id != base.toStopId else { return nil }
        let from = RideLogic.rideStopIdx(d.stops, fromStopId: base.fromStopId, toStopId: nil).from ?? 0
        guard let alight = RideLogic.alightAt(d.stops, d.times, last, .init(at: RideLogic.estimatedAt(d.stops, d.times, last), delayS: RideLogic.nearestDelayS(d.times, last))) else { return nil }
        let distance = RideLogic.pathLengthM(d.stops, from: from, to: last)
        let loopEnd = d.loopEnd
        return { r in
            r.toStopId = alight.toStopId
            r.toStopName = alight.toStopName
            r.alightedAt = alight.alightedAt
            r.delayAtAlightS = alight.delayAtAlightS
            r.stops = last - from
            r.distanceM = distance
            r.endedBy = nil
            r.loopEnd = loopEnd
        }
    }

    private func loadBase() async {
        guard let base, let d = try? await APIClient.shared.rideTrip(tripId: base.tripId, date: base.serviceDate), let stops = d.stops, !stops.isEmpty else { return }
        baseDetail = Detail(stops: stops, times: RideLogic.stopTimes(d.events ?? []), loopEnd: d.loopEnd ?? false)
    }

    private func loadDetail() async {
        detail = nil
        detailFailed = false
        guard let current else { return }
        guard let d = try? await APIClient.shared.rideTrip(tripId: current.trip.tripId, date: current.trip.serviceDate) else {
            detailFailed = true
            return
        }
        guard let stops = d.stops, !stops.isEmpty else {
            detailFailed = true
            return
        }
        detail = Detail(stops: stops, times: RideLogic.stopTimes(d.events ?? []), loopEnd: d.loopEnd ?? false)
    }

    // MARK: - Steps

    private func startLeg(_ trip: PastTripRow, continued: Bool) {
        let vehicleId = continued ? (prevVehicle.isEmpty ? trip.run?.vehicleId ?? "" : prevVehicle) : (trip.run?.vehicleId ?? "")
        legs.append(LegDraft(
            trip: trip,
            vehicleId: vehicleId,
            vehicleKnown: !vehicleId.isEmpty && (continued || trip.run != nil),
            fixedFrom: continued,
            from: continued ? 0 : nil,
            to: nil
        ))
        mode = continued ? .to : .from
        step = .leg
    }

    private func patchCurrent(_ change: (inout LegDraft) -> Void) {
        guard !legs.isEmpty else { return }
        change(&legs[legs.count - 1])
    }

    private func back() {
        switch step {
        case .trips: step = .pick
        case .next:
            patchCurrent { $0.done = nil }
            mode = .to
            step = .leg
        case .leg:
            legs.removeLast()
            step = legs.count >= 1 || base != nil ? .next : .trips
        case .pick: break
        }
    }

    /// The leg's fields from the chosen stops; where the bus has no event,
    /// estimated time and the nearest measured delay.
    private func legFields(_ leg: LegDraft, _ d: Detail, last: Bool) -> Ride? {
        guard let from = leg.from, let to = leg.to, to > from else { return nil }
        let est = { (idx: Int) in RideLogic.StopFallback(at: RideLogic.estimatedAt(d.stops, d.times, idx), delayS: RideLogic.nearestDelayS(d.times, idx)) }
        guard let board = RideLogic.boardAt(d.stops, d.times, from, est(from)),
              let alight = RideLogic.alightAt(d.stops, d.times, to, est(to)) else { return nil }
        let t = leg.trip
        return Ride(
            id: "", serviceDate: t.serviceDate, vehicleId: leg.vehicleId.trimmingCharacters(in: .whitespaces), tripId: t.tripId,
            route: t.route, headsign: t.headsign, color: t.color, text: t.text, boardedAt: board.boardedAt,
            alightedAt: alight.alightedAt, fromStopId: board.fromStopId, fromStopName: board.fromStopName,
            toStopId: alight.toStopId, toStopName: alight.toStopName, stops: to - from,
            distanceM: RideLogic.pathLengthM(d.stops, from: from, to: to), delayAtBoardS: board.delayAtBoardS,
            delayAtAlightS: alight.delayAtAlightS, detected: .later, endedBy: last ? .user : nil, editedAt: nil, loopEnd: d.loopEnd
        )
    }

    private func stay() {
        guard let current, let detail, let done = legFields(current, detail, last: false) else { return }
        patchCurrent { $0.done = done }
        step = .next
    }

    private func save() {
        guard let current, let detail else { return }
        let fields = legs.dropLast().map(\.done) + [legFields(current, detail, last: true)]
        let complete = fields.compactMap { $0 }
        guard complete.count == fields.count else { return }
        let ids = complete.map { _ in UUID().uuidString.lowercased() }
        let chainId = base.map { $0.chainId ?? $0.id } ?? (complete.count > 1 ? ids.first : nil)
        if let base, let baseFix { store.patchRides([base.id: baseFix]) }
        store.addRides(zip(complete, ids).map { r, id in
            var next = r
            next.id = id
            next.chainId = chainId
            return next
        })
        dismiss()
    }

    // MARK: - Leg

    @ViewBuilder
    private func legStops(_ leg: LegDraft) -> some View {
        if detailFailed {
            RideMessage(text: "Ennek a menetnek a megállói nem érhetők el.")
        } else if let detail {
            let n = detail.stops.count
            let lo = mode == .from ? 0 : (leg.from ?? 0) + 1
            let hi = mode == .from ? (leg.to ?? n - 1) - 1 : n - 1
            let nameOf = { (idx: Int?) in idx.flatMap { detail.stops.indices.contains($0) ? detail.stops[$0].name : nil } ?? "Válaszd ki" }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Busz:").foregroundStyle(Theme.mutedForeground)
                    if leg.vehicleKnown {
                        Text(TransitIds.displayVehicleId(leg.vehicleId))
                            .font(Theme.mono(12.5, weight: .bold))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    } else {
                        TextField("pályaszám, ha tudod", text: Binding(
                            get: { leg.vehicleId },
                            set: { value in
                                let clean = String(value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }.prefix(12))
                                patchCurrent { $0.vehicleId = clean }
                            }
                        ))
                        .font(Theme.mono(13, weight: .regular))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 10)
                        .frame(width: 176, height: 34)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.input, lineWidth: 1))
                        .accessibilityLabel("A busz pályaszáma")
                    }
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                RideModeTabs(mode: $mode, fromName: nameOf(leg.from), toName: nameOf(leg.to), fromLocked: leg.fixedFrom)
                    .padding(.horizontal, 20)
                StopChoiceList(
                    stops: detail.stops,
                    lo: lo,
                    hi: hi,
                    times: detail.times,
                    timeOf: mode == .from ? .dep : .arr,
                    selected: mode == .from ? leg.from : leg.to,
                    onPick: { idx in
                        let picking = mode
                        patchCurrent { if picking == .from { $0.from = idx } else { $0.to = idx } }
                        if picking == .from, leg.to == nil { mode = .to }
                    }
                )
                .id(mode)
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        } else {
            RideMessage(text: "A menet megállóit töltöm…")
        }
    }

    private func footer(_ leg: LegDraft) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1)
            VStack(spacing: 8) {
                if let to = leg.to, let n = detail?.stops.count, n > 0, to == n - 1 {
                    RideButton(title: "A buszon maradtam, tovább utaztam", systemImage: "repeat", variant: .outline, fullWidth: true, action: stay)
                        .disabled(leg.from == nil)
                }
                RideButton(title: "Mentés", fullWidth: true, action: save)
                    .disabled(leg.from == nil || leg.to == nil || detail == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    /// The pickable calendar days (Budapest wall clock), today first.
    static func recentDays() -> [(iso: String, label: String)] {
        let today = ServiceClock.at(Int(RealtimeClient.shared.serverNow)).calendarIso
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "hu_HU")
        weekday.timeZone = TimeZone(identifier: "UTC")
        weekday.dateFormat = "EEE"
        return (0..<daysBack).map { i in
            let iso = ServiceClock.shiftIso(today, by: -i)
            if i == 0 { return (iso, "Ma") }
            if i == 1 { return (iso, "Tegnap") }
            let parts = iso.split(separator: "-").compactMap { Int($0) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            let date = parts.count == 3 ? calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) : nil
            let wd = date.map { weekday.string(from: $0).replacingOccurrences(of: ".", with: "") } ?? ""
            return (iso, "\(wd.capitalized) \(parts.last ?? 0).")
        }
    }
}

private struct RideDayRoutePicker: View {
    let days: [(iso: String, label: String)]
    @Binding var day: String
    let favorites: [String]
    let onRoute: (PastRoute) -> Void

    @State private var routes: [PastRoute]?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(days, id: \.iso) { d in
                            let on = d.iso == day
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                day = d.iso
                            } label: {
                                Text(d.label)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(on ? Theme.primary : Theme.mutedForeground)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(on ? Theme.primary.opacity(0.12) : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(on ? Theme.primary.opacity(0.6) : Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 12)

                if failed || routes?.isEmpty == true {
                    RideMessage(text: "Erre a napra nincs menetrend.")
                } else if let routes {
                    let fav = favorites.compactMap { s in routes.first { $0.short == s } }
                    if !fav.isEmpty {
                        label("Gyakori vonalaid")
                        tiles(fav, prefix: "fav").padding(.bottom, 12)
                    }
                    label("Minden vonal")
                    tiles(routes, prefix: "all")
                } else {
                    RideMessage(text: "A nap vonalait töltöm…")
                }
            }
            .padding(.bottom, 20)
        }
        .task(id: day) {
            routes = nil
            failed = false
            do {
                routes = try await APIClient.shared.rideLogRoutes(date: day)
            } catch {
                failed = true
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Theme.mutedForeground)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
    }

    private func tiles(_ list: [PastRoute], prefix: String) -> some View {
        FlowLayout(spacing: 2) {
            ForEach(list) { r in
                Button { onRoute(r) } label: {
                    RouteTile(short: r.short, colorHex: r.color, textHex: r.text, size: .large)
                        .padding(4)
                }
                .buttonStyle(RidePressStyle())
                .accessibilityLabel("\(r.short): \(r.long)")
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct RideTripPicker: View {
    let date: String
    let today: Bool
    let route: String
    let onPick: (PastTripRow) -> Void

    @State private var trips: [PastTripRow]?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                RideMessage(text: "Most nem érem el a menetrendet. Próbáld újra kicsit később.")
            } else if let trips {
                let now = RealtimeClient.shared.serverNow
                let shown = trips.filter { $0.depTs <= now + 120 }
                if shown.isEmpty {
                    RideMessage(text: "Ezen a napon eddig nem indult menet ezen a vonalon.")
                } else {
                    PastTripList(trips: shown, focusId: today ? shown.last?.tripId : nil, onPick: onPick)
                }
            } else {
                RideMessage(text: "A menetrendet töltöm…")
            }
        }
        .task(id: "\(date)|\(route)") {
            do {
                trips = try await APIClient.shared.rideLogTrips(date: date, route: route)
            } catch {
                failed = true
            }
        }
    }
}

private struct RideNextPicker: View {
    let date: String
    let trip: String
    let vehicle: String
    let onPick: (PastTripRow) -> Void

    @State private var choices: [PastTripRow]?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                RideMessage(text: "Most nem érem el a menetrendet. Próbáld újra kicsit később.")
            } else if let choices {
                if choices.isEmpty {
                    RideMessage(text: "A végállomásról nem indult tovább menet 45 percen belül.")
                } else {
                    PastTripList(
                        trips: choices,
                        focusId: choices.first?.tripId,
                        badge: { c in c.sameVehicle == true ? "ez a busz" : c.kind == "nearby" ? "szomszéd kocsiállás" : nil },
                        onPick: onPick
                    )
                }
            } else {
                RideMessage(text: "Megnézem, merre ment tovább…")
            }
        }
        .task(id: "\(date)|\(trip)|\(vehicle)") {
            do {
                choices = try await APIClient.shared.rideLogNext(serviceDate: date, tripId: trip, vehicleId: vehicle)
            } catch {
                failed = true
            }
        }
    }
}
