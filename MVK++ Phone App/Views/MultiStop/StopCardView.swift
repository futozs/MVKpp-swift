//
//  StopCardView.swift
//  MVK++ Phone App
//

import SwiftUI

/// Moving a card earlier or later while the Figyelő is being reordered.
struct StopCardReorder {
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let canMoveEarlier: Bool
    let canMoveLater: Bool
}

/// One watched stop — the web app's `StopCard`: the next departure in full
/// (with its insights and vehicle), then the ones after it.
struct StopCardView: View {
    let stop: Stop
    var distanceKm: Double?
    var isNearest = false
    var reorder: StopCardReorder?
    var onRemove: (String) -> Void
    var onFocusMap: (Stop, String?, String?) -> Void

    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var location: LocationProvider
    @ObservedObject private var notifications = NotificationCenterStore.shared
    @ObservedObject private var features = WatchFeatures.shared
    @ObservedObject private var alerts = AlertsStore.shared

    @StateObject private var model = StopArrivalsModel()
    @State private var isNotifyOpen = false
    @State private var leaveBusy = false
    @State private var leaveNote: String?

    private var isStation: Bool { StopKind.isStation(stop.id) }
    private var listLimit: Int { isStation ? 12 : 8 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            let catchFor = CatchFor(stopLat: stop.lat, stopLon: stop.lon, position: location.position, now: RealtimeClient.shared.serverNow)
            BoardCard(highlighted: isNearest) {
                header
                HairlineDivider()
                nextDeparture(catchFor)
                HairlineDivider()
                laterDepartures(catchFor)
            }
        }
        .task(id: stop.id) { await model.start(stopId: stop.id, stopName: stop.name, limit: listLimit) }
        .onDisappear { model.stop() }
        .sheet(isPresented: $isNotifyOpen) {
            StopNotifySheet(stop: stop, arrivals: model.arrivals)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.background)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.system(size: 16, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let distanceKm {
                        Text(Geo.formatDistance(distanceKm))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.foreground)
                    }
                    Text(StopKind.label(stopId: stop.id))
                    if let merged = model.response?.merged, merged.count >= 2 {
                        Text("·")
                        SharedStopTag(merged: merged)
                    }
                    if isOnWatch {
                        Label("órán", systemImage: "applewatch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }
                .font(Theme.mono(11, weight: .regular))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                if let reorder {
                    OutlineIconButton(systemName: "chevron.left", label: "\(stop.name) előrébb helyezése", action: reorder.onMoveEarlier)
                        .disabled(!reorder.canMoveEarlier)
                    OutlineIconButton(systemName: "chevron.right", label: "\(stop.name) hátrébb helyezése", action: reorder.onMoveLater)
                        .disabled(!reorder.canMoveLater)
                }

                GhostIconButton(systemName: "scope", label: "\(stop.name) megjelenítése a térképen") {
                    onFocusMap(stop, nil, nil)
                }
                .contextMenu {
                    Button {
                        favorites.widgetStopId = isOnWatch ? nil : stop.id
                    } label: {
                        Label(isOnWatch ? "Levétel az óra widgetjéről" : "Megjelenítés az óra widgetjén",
                              systemImage: isOnWatch ? "applewatch.slash" : "applewatch")
                    }
                }

                let watching = notifications.hasWatch(stopId: stop.id)
                GhostIconButton(
                    systemName: watching ? "bell.and.waves.left.and.right.fill" : "bell",
                    label: "Értesítés beállítása \(stop.name)",
                    tint: watching ? Theme.primary : Theme.foreground
                ) {
                    isNotifyOpen = true
                }

                GhostIconButton(systemName: "trash", label: "\(stop.name) levétele a figyelőről", destructive: true) {
                    onRemove(stop.id)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var isOnWatch: Bool { favorites.widgetStopId == stop.id }

    // MARK: - Next departure

    private func nextDeparture(_ catchFor: CatchFor) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.error {
                RetryNotice(error: error).padding(.bottom, 10)
            }

            if model.response == nil && !model.isOffline {
                if model.error == nil {
                    BoardPlaceholder(text: "Indulások lekérése…", mono: true)
                }
            } else if let next = model.arrivals.first {
                hero(next, catchFor: catchFor)
            } else {
                BoardPlaceholder(text: "Ebben az órában nincs több indulás.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted.opacity(0.3))
    }

    private func hero(_ next: ArrivalItem, catchFor: CatchFor) -> some View {
        let arrivals = model.arrivals
        let verdict = catchFor.verdict(next)
        let catchable = verdict?.state == .missed
            ? arrivals.dropFirst().first { $0.route == next.route && catchFor.verdict($0)?.state != .missed }
            : nil
        let heroEta: Int = {
            guard features.isOn(.startRisk), next.startRisk != nil, next.schedUnix != nil else { return next.etaMin }
            let expected = CatchBus.expectedArrival(next, now: catchFor.now).at
            return max(next.etaMin, Int(((expected - catchFor.now) / 60).rounded()))
        }()
        let leaveSlot = "leave:\(next.tripId)"
        let leaveOn = alerts.has(stopId: stop.id, slot: leaveSlot)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                BoardEyebrow(text: "Következő")
                Spacer()
                if next.isCancelled {
                    CancelledTag(prominent: true)
                } else if model.isOffline {
                    OfflineTag(compact: true)
                } else {
                    LiveTag(live: next.live)
                }
            }
            .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 12) {
                RouteTile(short: next.tileText, colorHex: next.color, textHex: next.text, size: .large)

                VStack(alignment: .leading, spacing: 6) {
                    Text(next.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    FlowLayout(spacing: 8, lineSpacing: 4) {
                        Text(next.time)
                            .font(Theme.mono(12, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                            .strikethrough(next.isCancelled, color: Theme.destructive.opacity(0.7))
                        PlatformBadge(
                            platform: next.platform,
                            changed: next.platformChanged == true,
                            predicted: next.platformPredicted == true,
                            mode: next.mode
                        )
                        if !next.isCancelled {
                            DelayBar(delaySec: next.delaySec ?? next.measuredDelaySec)
                        }
                    }
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)

                if next.isCancelled {
                    Text("nem jön")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.destructive)
                        .padding(.top, 4)
                } else {
                    CountdownView(etaMin: heroEta)
                }
            }

            NoticeList(notices: next.notices).padding(.top, next.notices?.isEmpty == false ? 10 : 0)

            if next.isCancelled, features.isOn(.replacement) {
                ReplacementNote(instead: Replacement.instead(of: next, in: arrivals), cancelled: next)
            }

            if next.vehicle == nil, let predicted = next.predictedVehicle, features.isOn(.predictedVehicle),
               !next.isCancelled, next.mode != .rail {
                predictedLine(predicted).padding(.top, 12)
            }

            if features.isOn(.forecast), let upper = next.forecastUpperSec, DelayFormat.state(upper) == .late {
                ForecastLine(delayS: next.forecastDelaySec, upperS: upper, mode: .worst).padding(.top, 10)
            }
            if features.isOn(.startRisk), next.startRisk != nil {
                StartRiskLine(risk: next.startRisk).padding(.top, 8)
            }
            if features.isOn(.traffic), next.trafficAhead != nil {
                TrafficLine(traffic: next.trafficAhead).padding(.top, 8)
            }
            if features.isOn(.catchBus), let verdict {
                CatchLine(
                    verdict: verdict,
                    next: catchable,
                    alertOn: leaveOn,
                    alertBusy: leaveBusy,
                    onToggleAlert: { Task { await toggleLeave(next, slot: leaveSlot, on: leaveOn, walkS: catchFor.walkS) } }
                )
                .padding(.top, 10)
                if let leaveNote {
                    Text(leaveNote)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.top, 4)
                }
            }
            if features.isOn(.vehicleTrack) {
                VehicleTrackView(
                    vehicle: next.vehicle,
                    label: next.mode == .rail ? next.tileText : nil,
                    progressDesc: next.progressDesc,
                    onTrack: next.vehicle == nil ? nil : { onFocusMap(stop, next.tripId, next.vehicle?.id) }
                )
                .padding(.top, next.vehicle != nil || next.progressDesc != nil ? 12 : 0)
            }
        }
    }

    private func predictedLine(_ predicted: PredictedVehicle) -> some View {
        let id = TransitIds.displayVehicleId(predicted.id)
        let loop = PredictedVehicleTag.isLoop(predicted)
        return HStack(spacing: 4) {
            Text(loop ? "A" : "Várhatóan a")
            PredictedVehicleTag(predicted: predicted)
            Text(loop ? "jön: most a végállomás felé tart, onnan fordul vissza" : "jön")
                .lineLimit(2)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.mutedForeground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loop ? "A \(id) jön: most a végállomás felé tart, onnan fordul vissza" : "Várhatóan a \(id) jön")
        .accessibilityHint(PredictedVehicleTag.title(predicted))
    }

    private func toggleLeave(_ next: ArrivalItem, slot: String, on: Bool, walkS: Double?) async {
        guard let walkS else { return }
        leaveBusy = true
        leaveNote = nil
        defer { leaveBusy = false }
        if on {
            await alerts.remove(stopId: stop.id, slot: slot)
            return
        }
        let result = await alerts.add(
            slot: slot,
            kind: "leave",
            stopId: stop.id,
            stopName: stop.name,
            tripId: next.tripId,
            params: ["walkS": .number(walkS)]
        )
        if !result.ok {
            leaveNote = result.reason ?? "Nem sikerült bekapcsolni."
        } else {
            if !result.push { leaveNote = result.noPushNote }
            alerts.boardUpdated(stopId: stop.id, arrivals: model.arrivals)
        }
    }

    // MARK: - Later departures

    private func laterDepartures(_ catchFor: CatchFor) -> some View {
        let rest = Array(model.arrivals.dropFirst().prefix(isStation ? 10 : 5))
        return ScrollView {
            LazyVStack(spacing: 0) {
                if rest.isEmpty {
                    if !model.arrivals.isEmpty {
                        Text("Nincs több ismert indulás.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                } else {
                    ForEach(Array(rest.enumerated()), id: \.offset) { index, arrival in
                        if index > 0 { HairlineDivider(opacity: 0.6) }
                        ArrivalRowView(
                            arrival: arrival,
                            variant: .card,
                            list: model.arrivals,
                            verdict: catchFor.verdict(arrival)
                        ) { tripId, vehicleId in
                            onFocusMap(stop, tripId, vehicleId)
                        }
                    }
                }
            }
        }
    }
}
