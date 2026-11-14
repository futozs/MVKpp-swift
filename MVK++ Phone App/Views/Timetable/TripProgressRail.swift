//
//  TripProgressRail.swift
//  MVK++ Phone App
//

import SwiftUI

/// A live run as a vertical line: the stops in order with their timetable
/// times, the line filled up to the vehicle, and the vehicle itself riding
/// between two stops. Port of the web's `TripProgressRail`.
struct TripProgressRail: View {
    let trip: TimetableTrip
    let vehicleId: String?
    let stopNames: [String]

    @StateObject private var model = TripProgressModel()
    @Environment(\.isTabActive) private var isTabActive

    private let rowHeight: CGFloat = 34
    private let railX: CGFloat = 71

    var body: some View {
        Group {
            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else if let data = model.progress {
                content(data)
            } else {
                Text("Haladás lekérése…")
                    .font(Theme.mono(12, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
        .task(id: "\(trip.tripId)|\(vehicleId ?? "")|\(isTabActive)") {
            if isTabActive { await model.start(tripId: trip.tripId, vehicleId: vehicleId) } else { model.stop() }
        }
        .onDisappear { model.stop() }
    }

    private struct RailStop: Identifiable {
        let index: Int
        let id: String
        let name: String
        let time: String?
    }

    private func content(_ data: TripProgressResponse) -> some View {
        let stops: [RailStop] = data.stops.isEmpty
            ? stopNames.enumerated().map { RailStop(index: $0.offset, id: "\($0.offset)", name: $0.element, time: time($0.offset)) }
            : data.stops.enumerated().map { RailStop(index: $0.offset, id: $0.element.id, name: $0.element.name, time: time($0.offset)) }
        let segment = data.segmentIndex
        let fraction = data.segmentFraction ?? 0
        let busTop = segment.map { (CGFloat($0) + CGFloat(fraction)) * rowHeight + rowHeight / 2 }

        return VStack(alignment: .leading, spacing: 8) {
            if data.live, let vehicle = data.vehicle {
                FlowLayout(spacing: 10, lineSpacing: 4) {
                    Text(TransitIds.displayVehicleId(vehicle.id))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(subtitle(data))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                    if DelayFormat.state(data.scheduleDeviationSec) != .unknown {
                        HStack(spacing: 6) {
                            DelayBar(delaySec: data.scheduleDeviationSec, showLabel: false)
                            Text(DelayFormat.sentence(data.scheduleDeviationSec))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DelayFormat.tone(data.scheduleDeviationSec))
                        }
                    }
                }
            } else {
                Text("Erre a menetre még nem jelentkezett be jármű.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
            }

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Theme.border)
                    .frame(width: 2, height: CGFloat(stops.count) * rowHeight)
                    .offset(x: railX - 1)

                if let busTop {
                    Capsule()
                        .fill(Theme.primary)
                        .frame(width: 2, height: busTop)
                        .offset(x: railX - 1)
                        .animation(Theme.Motion.normalAnimation, value: busTop)
                }

                VStack(spacing: 0) {
                    ForEach(stops) { stop in
                        row(stop, segment: segment)
                    }
                }

                if let busTop, data.live {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primaryForeground)
                        .frame(width: 28, height: 28)
                        .background(Theme.primary, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
                        .mvkShadow(Theme.Shadow.md)
                        .offset(x: railX + 1 - 14, y: busTop - 14)
                        .animation(Theme.Motion.normalAnimation, value: busTop)
                        .accessibilityLabel(data.nextStop.map { "Következő megálló: \($0.name)" } ?? "A jármű útközben")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func row(_ stop: RailStop, segment: Int?) -> some View {
        let passed = segment.map { stop.index <= $0 } ?? false
        let isNext = segment.map { stop.index == $0 + 1 } ?? false
        return HStack(spacing: 0) {
            Text(stop.time ?? "")
                .font(Theme.mono(12, weight: .regular))
                .foregroundStyle(passed ? Theme.mutedForeground.opacity(0.6) : Theme.mutedForeground)
                .frame(width: 52, alignment: .trailing)

            Circle()
                .fill(passed ? Theme.primary : Theme.background)
                .overlay(Circle().strokeBorder(passed || isNext ? Theme.primary : Theme.border, lineWidth: 2))
                .frame(width: 10, height: 10)
                .frame(width: 38)

            Text(stop.name)
                .font(.system(size: 12, weight: isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? Theme.foreground : passed ? Theme.mutedForeground.opacity(0.6) : Theme.mutedForeground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func time(_ index: Int) -> String? {
        trip.times.indices.contains(index) ? trip.times[index] : nil
    }

    private func subtitle(_ data: TripProgressResponse) -> String {
        var text = data.nextStop.map { "következő: \($0.name)" } ?? "útközben"
        if let speed = data.vehicle?.speed {
            text += " · \(Int((speed * 3.6).rounded())) km/h"
        }
        return text
    }
}
