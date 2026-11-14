//
//  CommuteCard.swift
//  MVK++ Phone App
//

import SwiftUI

/// „Szokásos utad” — a regular trip recognised from the ride log, at the top
/// of the Figyelő from an hour and a half before its usual time. Shows the
/// next departure, whether you can catch it, and can remind you every such
/// day. The web app's `CommuteCard`.
struct CommuteCard: View {
    @ObservedObject private var rideLog = CommuteRideLog.shared
    @ObservedObject private var features = WatchFeatures.shared
    @ObservedObject private var alerts = AlertsStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let now = RealtimeClient.shared.serverNow
            if features.isOn(.commute),
               let commute = Commute.upcoming(Commute.detect(rideLog.rides, now: now), now: now) {
                CommuteCardBody(commute: commute, now: now, alerts: alerts)
            }
        }
    }
}

private struct CommuteCardBody: View {
    let commute: Commute
    let now: Double
    @ObservedObject var alerts: AlertsStore

    @EnvironmentObject private var location: LocationProvider
    @ObservedObject private var features = WatchFeatures.shared
    @StateObject private var model = StopArrivalsModel()
    @Environment(\.isTabActive) private var isTabActive
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        let response = model.response
        let catchFor = CatchFor(stopLat: response?.stop.lat, stopLon: response?.stop.lon, position: location.position, now: now)
        let departure = response.flatMap { pick($0.arrivals) }
        let verdict = departure.flatMap { catchFor.verdict($0) }
        let daily = alerts.alert(stopId: commute.fromStopId, slotPrefix: "commute:\(commute.route):")
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Text("Szokásos utad · ~\(BudapestClock.hm(minute: commute.minute))")
                    .font(Theme.sans(11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.275)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                dailyButton(daily: daily, departure: departure, walkS: catchFor.walkS)
            }
            .foregroundStyle(Theme.primary)

            HStack(spacing: 10) {
                RouteTile(short: commute.route, colorHex: departure?.color ?? commute.color, textHex: departure?.text ?? commute.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Text(commute.fromStopName)) \(Text(commute.loop ? "· körbeutazás" : "→ \(commute.toStopName ?? commute.headsign)").foregroundStyle(Theme.mutedForeground))")
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let departure {
                            Text(departure.time)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.foreground)
                            DelayBar(delaySec: departure.delaySec ?? departure.measuredDelaySec, showLabel: false)
                        } else {
                            Text(response == nil ? "Indulások lekérése…" : "Most nincs közeli indulás ezen a vonalon.")
                                .font(Theme.sans(11))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    Text("\(commute.rides) út · \(commute.daysText)")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let departure {
                    let eta = max(0, Int(((CatchBus.expectedArrival(departure, now: now).at - now) / 60).rounded()))
                    Group {
                        if eta <= 0 {
                            Text("most").font(Theme.mono(18)).foregroundStyle(Theme.live)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(eta)").font(Theme.mono(18)).foregroundStyle(Theme.foreground)
                                Text("p").font(Theme.sans(11, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
                            }
                        }
                    }
                    .fixedSize()
                }
            }
            .padding(.top, 8)

            if let departure {
                if features.isOn(.startRisk), departure.startRisk != nil {
                    StartRiskLine(risk: departure.startRisk).padding(.top, 6)
                }
                if features.isOn(.traffic), departure.trafficAhead != nil {
                    TrafficLine(traffic: departure.trafficAhead).padding(.top, 6)
                }
                if features.isOn(.catchBus), verdict != nil {
                    CatchLine(verdict: verdict).padding(.top, 8)
                }
            }

            if let note {
                Text(note)
                    .font(Theme.sans(10.5))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.primary.opacity(0.06), in: shape)
        .overlay(shape.strokeBorder(Theme.primary.opacity(0.30), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Szokásos utad")
        .task(id: "\(commute.fromStopId)|\(isTabActive)") {
            if isTabActive { await model.start(stopId: commute.fromStopId, stopName: commute.fromStopName, limit: 12) } else { model.stop() }
        }
        .onDisappear { model.stop() }
    }

    private func dailyButton(daily: AlertWatch?, departure: ArrivalItem?, walkS: Double?) -> some View {
        let on = daily != nil
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        return Button {
            Task { await toggleDaily(daily, departure: departure, walkS: walkS) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: on ? "bell.and.waves.left.and.right.fill" : "repeat")
                    .font(.system(size: 10, weight: .bold))
                Text(on ? "Szólok ilyenkor" : "Szólj ilyenkor")
                    .font(Theme.sans(11, weight: .semibold))
            }
            .foregroundStyle(on ? Theme.primaryForeground : Theme.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(on ? Theme.primary : Color.clear, in: shape)
            .overlay(shape.strokeBorder(on ? Theme.primary : Theme.primary.opacity(0.4), lineWidth: 1))
            .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on
            ? "\(capitalized(commute.daysText)) szólok, amikor indulni kell. Koppints a kikapcsoláshoz"
            : "Szólj \(commute.daysText), amikor indulnom kell")
    }

    /// The usual departure today: same line (same direction if possible), the
    /// not yet gone departure closest to the usual time.
    private func pick(_ arrivals: [ArrivalItem]) -> ArrivalItem? {
        let same = arrivals.filter { $0.route == commute.route && !$0.isCancelled }
        let direction = same.filter { $0.headsign == commute.headsign }
        let pool = (direction.isEmpty ? same : direction).filter { CatchBus.expectedArrival($0, now: now).at >= now - 30 }
        func off(_ arrival: ArrivalItem) -> Double {
            arrival.schedUnix.map { Double(abs(BudapestClock.minute($0) - commute.minute)) } ?? .infinity
        }
        var best: ArrivalItem?
        for arrival in pool where best.map({ off(arrival) < off($0) }) ?? true { best = arrival }
        return best
    }

    private func toggleDaily(_ daily: AlertWatch?, departure: ArrivalItem?, walkS: Double?) async {
        busy = true
        note = nil
        defer { busy = false }
        if let daily {
            await alerts.remove(stopId: daily.stopId, slot: daily.slot)
            return
        }
        let schedMin = departure?.schedUnix.map(BudapestClock.minute) ?? commute.minute
        let walk = walkS ?? 0
        let days: AlertParam = commute.daily ? .string(commute.dayKind.rawValue) : .numbers(commute.dows.map(Double.init))
        let result = await alerts.add(
            slot: "commute:\(commute.route):\(schedMin)",
            kind: "leave",
            stopId: commute.fromStopId,
            stopName: commute.fromStopName,
            routeShorts: [commute.route],
            schedMin: schedMin,
            params: ["walkS": .number(walk), "days": days]
        )
        if !result.ok {
            note = result.reason ?? "Nem sikerült bekapcsolni."
        } else {
            let walkText = walk > 0 ? " (\(Int((walk / 60).rounded())) perc séta innen)" : ""
            note = "\(capitalized(commute.daysText)) \(BudapestClock.hm(minute: schedMin))-ra szólok, amikor indulni kell\(walkText).\(result.push ? "" : " \(result.noPushNote)")"
        }
    }

    private func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
