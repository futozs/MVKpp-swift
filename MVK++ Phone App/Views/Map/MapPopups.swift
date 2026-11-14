//
//  MapPopups.swift
//  MVK++ Phone App
//

import SwiftUI

/// A popup over the map: the web's Leaflet bubble, here a card floating at
/// the bottom of the map.
struct MapPopupCard<Content: View>: View {
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .padding(.trailing, 18)
            .frame(maxWidth: 340, alignment: .leading)
            .background(Theme.popover, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border))
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bezárás")
            }
            .mvkShadow(Theme.Shadow.xl)
    }
}

/// A vehicle's bubble (`vehiclePopup.ts`): route and destination, the delay
/// in words, plate or train number, speed, and „Követés” / „Felszálltam”.
struct MapVehiclePopup: View {
    let vehicle: LiveVehicle
    /// While riding the other vehicles are only for looking at.
    let actions: Bool
    var onFollow: () -> Void
    var onBoard: () -> Void
    var onClose: () -> Void

    var body: some View {
        MapPopupCard(onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Text(vehicle.routeShort)
                        .font(Theme.sans(14, weight: .heavy))
                        .foregroundStyle(Theme.hex(vehicle.routeText, fallback: .white))
                        .padding(.horizontal, 8)
                        .frame(minWidth: 40, minHeight: 26)
                        .background(Theme.hex(vehicle.routeColor), in: RoundedRectangle(cornerRadius: rail ? 13 : 8, style: .continuous))
                    Text(vehicle.headsign.isEmpty ? "Járat" : vehicle.headsign)
                        .font(Theme.sans(13.5, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(2)
                }

                if let delayLine {
                    Text(delayLine.text)
                        .font(Theme.sans(17, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(delayLine.tone)
                        .padding(.top, 12)
                }

                Text(meta)
                    .font(Theme.sans(12).monospacedDigit())
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.top, delayLine == nil ? 12 : 2)

                if actions, !vehicle.tripId.isEmpty {
                    HStack(spacing: 6) {
                        Button(action: onFollow) {
                            Text("Követés")
                                .font(Theme.sans(12.5, weight: .bold))
                                .foregroundStyle(Theme.foreground)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border))
                        }
                        Button(action: onBoard) {
                            Text("Felszálltam")
                                .font(Theme.sans(12.5, weight: .bold))
                                .foregroundStyle(Theme.primaryForeground)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }
            }
        }
    }

    private var rail: Bool { vehicle.mode == .rail }

    private var delayLine: (text: String, tone: Color)? {
        guard let delay = VehicleFilter.delay(vehicle) else { return nil }
        let mav = vehicle.delaySec != nil && vehicle.mode != .bus && vehicle.mode != .tram ? " (MÁV)" : ""
        let minutes = Int((Double(abs(delay)) / 60).rounded())
        if abs(delay) < 60 { return ("Pontos\(mav)", Theme.ontime) }
        return delay > 0 ? ("\(minutes) perc késés\(mav)", Theme.late) : ("\(minutes) perccel korábban\(mav)", Theme.early)
    }

    private var meta: String {
        let idTitle = rail ? "Vonat" : "Rendszám"
        let trainText = "\(vehicle.trainNo ?? "")\(vehicle.trainName.map { " \($0)" } ?? "")".trimmingCharacters(in: .whitespaces)
        let idText = rail ? (trainText.isEmpty ? "" : trainText) : TransitIds.displayVehicleId(vehicle.id, plate: vehicle.plate)
        return [
            "\(idTitle) \(idText)",
            vehicle.speedKmh.map { "\($0) km/h" },
            vehicle.estimated == true ? "menetrendből becsült helyzet" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A replayed vehicle's bubble (`useHistoryMarkers.ts`), refreshed as the
/// timeline plays.
struct MapHistoryPopup: View {
    let vehicleId: String
    let route: Route?
    let routeShort: String?
    let time: Double
    let sample: MapHistorySampler.Sample?
    var onClose: () -> Void

    var body: some View {
        MapPopupCard(onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Text(routeShort ?? "?")
                        .font(Theme.sans(14, weight: .heavy))
                        .foregroundStyle(Theme.hex(route?.text, fallback: .white))
                        .padding(.horizontal, 8)
                        .frame(minWidth: 40, minHeight: 26)
                        .background(Theme.hex(route?.color), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("VISSZAJÁTSZÁS")
                        .font(Theme.sans(11, weight: .bold))
                        .tracking(0.44)
                        .foregroundStyle(Theme.mutedForeground)
                }
                .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("RENDSZÁM")
                        .font(Theme.sans(10, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.mutedForeground)
                    Text(vehicleId)
                        .font(Theme.mono(20))
                        .foregroundStyle(Theme.foreground)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.primary.opacity(0.25)))
                .padding(.bottom, 8)

                VStack(spacing: 3) {
                    row("Időpont", MapHistoryTime.clock(time), strong: true)
                    row("Utolsó jel", sample.map { MapHistoryTime.clock($0.fixTs) } ?? "")
                    row("Irány", heading)
                    row("Sebesség", speed)
                }
                .font(Theme.mono(12, weight: .regular))
            }
        }
    }

    private func row(_ label: String, _ value: String, strong: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.mutedForeground)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(strong ? .bold : .regular)
                .foregroundStyle(Theme.foreground)
        }
    }

    private var motion: (bearing: Double?, speedKmh: Double?) {
        sample.map(MapHistorySampler.motion) ?? (nil, nil)
    }

    private var heading: String {
        guard let b = motion.bearing else { return "" }
        return "\(MapHistorySampler.compassLabel(b)) · \(Int(b.rounded()))°"
    }

    private var speed: String {
        guard let s = motion.speedKmh else { return "" }
        return "~\(Int(s.rounded())) km/h"
    }
}
