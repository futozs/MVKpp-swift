//
//  VehicleFocusCard.swift
//  MVK++ Phone App
//

import SwiftUI

/// The followed vehicle's card (`VehicleFocusCard.tsx`): which run, which
/// vehicle, how fast, whether the map follows it, „Felszálltam”, and how far
/// it still has to come to reach the rider.
struct VehicleFocusCard: View {
    let tripId: String
    let vehicleId: String?
    let stops: [Stop]
    let routes: [String: Route]
    @ObservedObject var model: TripPathModel
    let followPaused: Bool
    var onClose: () -> Void

    @ObservedObject private var rides = RideStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if let shownId, let data = model.path, rides.active == nil {
                Button {
                    RideBoarding.board(
                        BoardInfo(tripId: data.trip.isEmpty ? tripId : data.trip, vehicleId: shownId, route: data.route, color: data.color, text: data.text, headsign: data.headsign),
                        detected: .manual
                    )
                } label: {
                    Label("Felszálltam erre a \(tripMode.words.ra)", systemImage: "ticket")
                }
                .buttonStyle(.mvk(fullWidth: true))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            ApproachStripView(
                tripId: model.path?.trip ?? tripId,
                shape: model.shape,
                vehicle: model.vehicleFix,
                stops: stops,
                deviationSec: model.path?.vehicle?.delaySec ?? model.path?.scheduleDeviationSec
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .mvkShadow(Theme.Shadow.xl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Követett jármű")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RouteTile(short: tileText, colorHex: model.path?.color, textHex: model.path?.text, size: .large)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title ?? "Menet betöltése…")
                        .font(Theme.sans(14, weight: .bold))
                        .tracking(-0.35)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    if model.path?.vehicle != nil { LiveDot() }
                }

                FlowLayout(spacing: 12, lineSpacing: 4) {
                    if let idLabel {
                        Text(idLabel)
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .accessibilityLabel(shownId.map { TransitIds.vehicleIdTitle($0, plate: model.path?.vehicle?.plate) } ?? idLabel)
                    }
                    if let speedKmh {
                        HStack(spacing: 4) {
                            Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 12))
                            Text("\(speedKmh) km/h").font(Theme.mono(12, weight: .semibold))
                        }
                        .foregroundStyle(speedKmh > 2 ? Theme.foreground : Theme.mutedForeground)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "location")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.primary)
                        Text(status)
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -10)
            .padding(.top, -8)
            .accessibilityLabel("Menetkövetés vége")
        }
    }

    private var vehicle: ArrivalVehicle? { model.path?.vehicle }
    private var shownId: String? { vehicle?.id ?? vehicleId }

    private var tripMode: TransitMode {
        guard let shownId else { return .bus }
        let feed = TransitIds.rideMode(vehicleId: shownId, tripId: model.path?.trip ?? tripId)
        guard feed == .bus, let route = model.path?.route else { return feed }
        let type = routes.values.first { $0.short == route || $0.id == route }?.type
        return TransitIds.vehicleMode(id: shownId, mode: nil, routeType: type)
    }

    private var trainNo: String? { tripMode == .rail ? vehicle?.trainNo : nil }

    private var tileText: String {
        guard let path = model.path else { return "…" }
        return trainNo.map { "\(path.route) \($0)" } ?? path.route
    }

    private var title: String? {
        guard let path = model.path else { return nil }
        return vehicle?.trainName.map { "\($0) → \(path.headsign)" } ?? path.headsign
    }

    private var idLabel: String? { shownId.map { TransitIds.displayVehicleId($0, plate: vehicle?.plate) } }

    private var speedKmh: Int? { vehicle?.speed.map { Int(($0 * 3.6).rounded()) } }

    private var status: String {
        if model.isLost { return "A jármű kiesett a jelentésből" }
        return followPaused ? "Követés szünetel" : "A térkép követi"
    }
}

/// The followed vehicle's panel at the bottom of the map (`FocusDock.tsx`):
/// on a phone the card, with a train's timetable folded above it.
struct FocusDock: View {
    let tripId: String
    let vehicleId: String?
    let stops: [Stop]
    let routes: [String: Route]
    @ObservedObject var model: TripPathModel
    let followPaused: Bool
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if TransitFeed.of(id: tripId) == .rail {
                TripTimetable(tripId: tripId)
                    .id(tripId)
            }
            VehicleFocusCard(
                tripId: tripId, vehicleId: vehicleId, stops: stops, routes: routes,
                model: model, followPaused: followPaused, onClose: onClose
            )
        }
        .mapCover()
    }
}
