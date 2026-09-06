//
//  TimetableGridView.swift
//  MVK++ Phone App
//

import SwiftUI

/// The departure board: one row per hour, minutes as tappable chips.
///
/// This is the shape printed on every stop pole in the country, and copying it
/// means a rider can find their departure without learning anything new. The
/// colouring carries the live state on top: green for a run under way, struck
/// through for one that was pulled, outlined for the next one due.
struct TimetableGridView: View {
    let trips: [TimetableTrip]
    let vehicleByTrip: [String: LiveVehicle]
    let cancelledTripIds: Set<String>
    let selectedTripId: String?
    let nowSec: Int
    let day: DayRelation
    var onSelectTrip: (TimetableTrip) -> Void

    private struct HourRow: Identifiable {
        let hour: Int
        let trips: [TimetableTrip]
        var id: Int { hour }
    }

    var body: some View {
        ScrollViewReader { proxy in
            // Not lazy: a day is at most two dozen hour rows, and lazy content
            // has no id registered for a row that has never been on screen —
            // which silently broke the scroll-to-now below.
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    hourRow(row, isAlternate: index % 2 == 1)
                }
            }
            .task(id: trips.count) {
                guard let anchor = activeTripId else { return }
                // One runloop turn so the rows exist before we aim at them.
                await Task.yield()
                withAnimation(Theme.Motion.normalAnimation) {
                    proxy.scrollTo(anchor, anchor: .center)
                }
            }
        }
    }

    // MARK: - Rows

    private func hourRow(_ row: HourRow, isAlternate: Bool) -> some View {
        let isCurrentHour = row.hour == currentHour

        return HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .opacity(0.8)
                Text(String(format: "%02d", row.hour % 24))
                    .font(Theme.mono(17))
            }
            .foregroundStyle(Theme.primaryForeground)
            .frame(width: 68, height: 34)
            .background(
                isCurrentHour ? Theme.primary : Theme.primary.opacity(0.85),
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(row.trips) { trip in
                    minuteChip(trip)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isAlternate: isAlternate, isCurrentHour: isCurrentHour))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
        }
    }

    private func rowBackground(isAlternate: Bool, isCurrentHour: Bool) -> Color {
        if isCurrentHour { return Theme.primary.opacity(0.07) }
        return isAlternate ? Theme.muted.opacity(0.25) : .clear
    }

    private func minuteChip(_ trip: TimetableTrip) -> some View {
        let isCancelled = cancelledTripIds.contains(trip.tripId)
        let vehicle = isCancelled ? nil : vehicleByTrip[trip.tripId]
        // A live GPS match arrives by trip ID regardless of date, so only
        // today's board may read it as "this run is out there now".
        let isLive = day == .today && vehicle != nil
        let isNext = trip.tripId == nextTripId
        let isSelected = trip.tripId == selectedTripId
        let isPast = day == .today && trip.departureSec < nowSec && !isLive
        let minute = (trip.departureSec % 3600) / 60

        return Button {
            onSelectTrip(trip)
        } label: {
            Text(String(format: "%02d", minute))
                .font(Theme.mono(14, weight: .semibold))
                .strikethrough(isCancelled, color: Theme.destructive)
                .foregroundStyle(chipForeground(isCancelled: isCancelled, isLive: isLive, isPast: isPast))
                .frame(minWidth: 46, minHeight: 36)
                .padding(.horizontal, 4)
                .background(
                    chipBackground(isCancelled: isCancelled, isLive: isLive, isSelected: isSelected, isPast: isPast),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(
                            chipBorder(isCancelled: isCancelled, isLive: isLive, isSelected: isSelected, isNext: isNext, isPast: isPast),
                            lineWidth: 1
                        )
                )
                .overlay(alignment: .topTrailing) {
                    // This run ends somewhere other than the direction's usual
                    // terminus — worth a mark before someone boards it.
                    if trip.headsignDiffers && !isCancelled {
                        Circle()
                            .fill(isLive ? Theme.primaryForeground : Theme.early)
                            .frame(width: 6, height: 6)
                            .padding(3)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Detours off the standard path.
                    if trip.deviates && !isLive && !isCancelled {
                        Circle()
                            .fill(Theme.mutedForeground)
                            .frame(width: 4, height: 4)
                            .padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .id(trip.tripId)
        .accessibilityLabel(accessibilityLabel(trip, isCancelled: isCancelled, vehicle: vehicle))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func chipForeground(isCancelled: Bool, isLive: Bool, isPast: Bool) -> Color {
        if isCancelled { return Theme.destructive }
        if isLive { return Theme.primaryForeground }
        if isPast { return Theme.mutedForeground }
        return Theme.foreground
    }

    private func chipBackground(isCancelled: Bool, isLive: Bool, isSelected: Bool, isPast: Bool) -> Color {
        if isCancelled { return Theme.destructive.opacity(0.12) }
        if isLive { return Theme.primary }
        if isSelected { return Theme.primary.opacity(0.15) }
        if isPast { return Theme.muted.opacity(0.6) }
        return Theme.card
    }

    private func chipBorder(isCancelled: Bool, isLive: Bool, isSelected: Bool, isNext: Bool, isPast: Bool) -> Color {
        if isCancelled { return Theme.destructive.opacity(0.6) }
        if isLive || isSelected || isNext { return Theme.primary }
        if isPast { return .clear }
        return Theme.border
    }

    private func accessibilityLabel(_ trip: TimetableTrip, isCancelled: Bool, vehicle: LiveVehicle?) -> String {
        if isCancelled { return "\(trip.departure), \(trip.destinationName) — törölve" }
        let state = TripStatus.runState(
            TripStatus.RunInput(
                cancelled: false,
                hasLiveVehicle: vehicle != nil,
                departureSec: trip.departureSec,
                arrivalSec: trip.arrivalSec,
                nowSec: nowSec,
                day: day
            )
        )
        let status = TripStatus.runLabel(state, vehicleId: vehicle?.id)
        return [trip.departure, trip.destinationName, status].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: - Derived data

    private var rows: [HourRow] {
        Dictionary(grouping: trips) { $0.departureSec / 3600 }
            .map { HourRow(hour: $0.key, trips: $0.value.sorted { $0.departureSec < $1.departureSec }) }
            .sorted { $0.hour < $1.hour }
    }

    private var currentHour: Int { day == .today ? nowSec / 3600 : -1 }

    private var nextTripId: String? {
        guard day == .today else { return nil }
        return trips
            .filter { $0.departureSec >= nowSec && !cancelledTripIds.contains($0.tripId) }
            .min { $0.departureSec < $1.departureSec }?
            .tripId
    }

    /// What the board scrolls to on open: the latest run currently out there,
    /// or failing that the next one due.
    private var activeTripId: String? {
        guard day == .today else { return nil }
        let running = trips
            .filter { !cancelledTripIds.contains($0.tripId) && vehicleByTrip[$0.tripId] != nil }
            .max { $0.departureSec < $1.departureSec }
        return running?.tripId ?? nextTripId
    }
}
