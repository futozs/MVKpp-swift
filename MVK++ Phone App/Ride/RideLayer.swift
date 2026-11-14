//
//  RideLayer.swift
//  MVK++ Phone App
//

import SwiftUI

/// The map's ride layer (web `RideLayer`): the boarding question, the ride
/// panel and the summary after the ride. While riding the map follows the bus.
struct RideLayer: View {
    let vehicles: [LiveVehicle]
    /// The trip the map is following right now.
    let followingTripId: String?
    let onFollow: (_ tripId: String, _ vehicleId: String) -> Void
    let onStopFollow: () -> Void

    @ObservedObject private var store = RideStore.shared
    @ObservedObject private var controller = RideController.shared
    @State private var fixing: FixRequest?
    @State private var continuing: ContinueRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct FixRequest: Identifiable {
        let legs: [Ride]
        let initial: RideFixSheet.Mode
        var id: String { legs.map(\.id).joined() }
    }

    struct ContinueRequest: Identifiable {
        let legs: [Ride]
        var id: String { legs.map(\.id).joined() }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let candidate = controller.candidate, store.active == nil {
                    BoardingPrompt(
                        vehicle: candidate.vehicle,
                        onYes: controller.answerYes,
                        onNo: controller.answerNo
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if let ride = store.active {
                    RidePanel(
                        ride: ride,
                        following: followingTripId == ride.tripId,
                        onCancel: onStopFollow,
                        onRefollow: { onFollow(ride.tripId, ride.vehicleId) }
                    )
                    .id(ride.id)
                    .mapCover()
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                } else if let saved = controller.saved {
                    savedNote(saved.ride, atLoop: saved.atLoop)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(Theme.Motion.normalAnimation, value: controller.candidate?.vehicle.id)
        .animation(Theme.Motion.normalAnimation, value: store.active?.id)
        .animation(Theme.Motion.normalAnimation, value: controller.saved?.ride.id)
        .onAppear {
            if let ride = store.active { onFollow(ride.tripId, ride.vehicleId) }
        }
        .onChange(of: store.active.map { "\($0.tripId)|\($0.vehicleId)" }) { _, key in
            if let ride = store.active, key != nil { onFollow(ride.tripId, ride.vehicleId) }
        }
        .onChange(of: store.active?.id) { old, new in
            if old != nil, new == nil { onStopFollow() }
        }
        .sheet(item: $fixing) { request in
            RideFixSheet(legs: request.legs, initial: request.initial)
        }
        .sheet(item: $continuing) { request in
            RideAddSheet(continueFrom: request.legs)
        }
        .overlay(alignment: .top) {
            if let notice = controller.notice {
                RideNoticeBanner(text: notice) { controller.notice = nil }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }
        }
    }

    private func savedNote(_ ride: Ride, atLoop: Bool) -> some View {
        let legs = RideStore.journey(of: ride, in: store.rides)
        let canLoop = atLoop || ride.endedBy == .terminus
        return RideSavedNote(
            ride: ride,
            legs: legs,
            onClose: controller.dismissSaved,
            onFix: RideStore.canFix(legs) ? {
                fixing = FixRequest(legs: legs, initial: .to)
                controller.dismissSaved()
            } : nil,
            onContinue: {
                continuing = ContinueRequest(legs: legs)
                controller.dismissSaved()
            },
            onLoop: canLoop ? {
                Task {
                    if let fallback = await controller.loopFromSaved(onFollow: onFollow) {
                        continuing = ContinueRequest(legs: fallback)
                    }
                }
            } : nil,
            looping: controller.looping
        )
    }
}

/// „Éppen erre a buszra szálltál fel?” — the detector's question at the top of the map.
struct BoardingPrompt: View {
    let vehicle: LiveVehicle
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        let w = vehicle.rideMode.words
        let rail = vehicle.mode == .rail
        VStack(alignment: .leading, spacing: 0) {
            RideEyebrow(text: "Együtt mozogsz egy \(w.val)", systemImage: "bus.fill")
            HStack(spacing: 12) {
                RouteTile(
                    short: rail && vehicle.trainNo != nil ? "\(vehicle.routeShort) \(vehicle.trainNo ?? "")" : vehicle.routeShort,
                    colorHex: vehicle.routeColor,
                    textHex: vehicle.routeText,
                    size: .large
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Éppen erre a \(w.ra) szálltál fel?")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.foreground)
                    Text(vehicle.headsign)
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Text(rail ? (vehicle.trainName ?? "") : TransitIds.displayVehicleId(vehicle.id, plate: vehicle.plate))
                        .font(Theme.mono(12, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 8)
            HStack(spacing: 8) {
                RideButton(title: "Igen, felszálltam", systemImage: "checkmark", fullWidth: true, action: onYes)
                RideButton(title: "Nem", systemImage: "xmark", variant: .outline, action: onNo)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: 448)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).stroke(Theme.primary.opacity(0.4), lineWidth: 1))
        .mvkShadow(Theme.Shadow.xl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Felszállás felismerve")
    }
}

/// After the ride: a short summary (of the whole loop journey). At a turning
/// loop the loop journey starts from here; if the app closed it on its own
/// it stays until acknowledged, and the real stop can be marked.
struct RideSavedNote: View {
    let ride: Ride
    let legs: [Ride]
    let onClose: () -> Void
    var onFix: (() -> Void)?
    var onContinue: (() -> Void)?
    var onLoop: (() -> Void)?
    var looping = false

    var body: some View {
        let first = legs.first ?? ride
        let sum = { (pick: (Ride) -> Double?) -> Double? in
            legs.contains { pick($0) != nil } ? legs.reduce(0) { $0 + (pick($1) ?? 0) } : nil
        }
        let stops = sum { $0.stops.map(Double.init) }
        let distance = sum(\.distanceM)
        let mins = ride.alightedAt.map { max(1, Int((($0 - first.boardedAt) / 60).rounded())) }
        let ask = RideController.endedOnItsOwn(ride) && onFix != nil
        let title = ask
            ? (ride.endedBy == .terminus ? "Lezártam az utazásod a végállomáson" : "Úgy láttam, leszálltál, lezártam")
            : (legs.count > 1 ? "Körbeutazás elmentve · \(legs.count) menet" : "Utazás elmentve")
        let facts = [
            mins.map { "\($0) perc" },
            stops.map { "\(Int($0)) megálló" },
            RideFormat.km(distance),
            ride.vehicleId.isEmpty ? nil : ride.vehicleId,
        ].compactMap { $0 }.joined(separator: " · ")

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                RouteTile(short: ride.route, colorHex: ride.color, textHex: ride.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.sans(14, weight: .bold)).foregroundStyle(Theme.foreground)
                    Text("\(first.fromStopName ?? "?") → \(ride.toStopName ?? "?")")
                        .font(Theme.sans(12)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                    Text(facts).font(Theme.mono(12, weight: .regular)).foregroundStyle(Theme.foreground).padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bezárás")
            }
            if ask, let onFix {
                HStack(spacing: 8) {
                    RideButton(title: "Így jó", systemImage: "checkmark", size: .small, fullWidth: true, action: onClose)
                    RideButton(title: "Hol szálltam le?", systemImage: "mappin", variant: .outline, size: .small, fullWidth: true, action: onFix)
                }
                .padding(.top, 12)
            }
            if let onLoop {
                RideButton(
                    title: "Körbeutazok, a buszon maradtam",
                    systemImage: "repeat",
                    variant: ask ? .ghost : .outline,
                    size: .small,
                    fullWidth: true,
                    busy: looping,
                    iconTint: Theme.primary,
                    border: Theme.primary.opacity(0.5),
                    action: onLoop
                )
                .disabled(looping)
                .padding(.top, 10)
            } else if ride.endedBy == .terminus, let onContinue {
                RideButton(title: "A buszon maradtam, tovább utaztam", systemImage: "arrow.turn.down.right", variant: .ghost, size: .small, fullWidth: true, action: onContinue)
                    .padding(.top, 6)
            }
        }
        .padding(16)
        .frame(maxWidth: 448)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .mvkShadow(Theme.Shadow.xl)
    }
}

/// The „Felszálltam” shortcut's answer when the app is open.
struct RideNoticeBanner: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "ticket").foregroundStyle(Theme.primary)
            Text(text).font(Theme.sans(13)).foregroundStyle(Theme.foreground).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bezárás")
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .task {
            try? await Task.sleep(for: .seconds(6))
            onClose()
        }
    }
}
