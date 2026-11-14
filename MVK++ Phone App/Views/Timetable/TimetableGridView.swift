//
//  TimetableGridView.swift
//  MVK++ Phone App
//

import SwiftUI

/// The departure board: one row per hour, minutes as tappable chips — the
/// shape printed on every stop pole, with the live state on top: filled for a
/// run under way, tinted for one standing at the first stop, struck through
/// for one that was pulled, outlined for the next one due.
struct TimetableGridView: View {
    let trips: [TimetableTrip]
    let vehicleByTrip: [String: LiveVehicle]
    let cancelledTripIds: Set<String>
    let journal: [String: TripJournalEntry]
    let selectedTripId: String?
    let nowSec: Int
    let day: DayRelation
    let directionHeadsign: String
    var variantLabels: [String: String] = [:]
    let proxy: ScrollViewProxy
    var onSelectTrip: (TimetableTrip) -> Void

    @State private var scrolledTrips: [String] = []
    @State private var scrolledSelection: String?

    private struct HourRow: Identifiable {
        let hour: Int
        let trips: [TimetableTrip]
        var id: Int { hour }
    }

    var body: some View {
        // Not lazy: a day is at most two dozen hour rows, and lazy content has
        // no id registered for a row never on screen, which breaks scrollTo.
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                hourRow(row, isAlternate: index % 2 == 1)
                if index < rows.count - 1 {
                    Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                }
            }
        }
        .task(id: "\(tripIds.count)|\(tripIds.first ?? "")|\(selectedTripId ?? "")") {
            await scrollIfNeeded()
        }
    }

    /// Only a new board or a new selection scrolls; the "now" tick never yanks
    /// the board. A selection is kept visible, otherwise the run under way.
    private func scrollIfNeeded() async {
        let fresh = scrolledTrips != tripIds
        let newSelection = scrolledSelection != selectedTripId
        scrolledTrips = tripIds
        scrolledSelection = selectedTripId
        guard fresh || newSelection else { return }
        guard let target = selectedTripId ?? (fresh ? activeTripId : nil) else { return }
        await Task.yield()
        withAnimation(Theme.Motion.normalAnimation) {
            proxy.scrollTo(target, anchor: fresh ? .center : nil)
        }
    }

    // MARK: - Rows

    private func hourRow(_ row: HourRow, isAlternate: Bool) -> some View {
        let isCurrentHour = row.hour == currentHour

        return HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.8)
                Text(String(format: "%02d", row.hour % 24))
                    .font(Theme.mono(16))
            }
            .foregroundStyle(Theme.primaryForeground)
            .frame(width: 68)
            .padding(.vertical, 6)
            .frame(maxHeight: .infinity)
            .background(
                isCurrentHour ? Theme.primary : Theme.primary.opacity(0.85),
                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            )
            .mvkShadow(Theme.Shadow.sm)

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(row.trips) { trip in
                    minuteChip(trip)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isAlternate: isAlternate, isCurrentHour: isCurrentHour))
    }

    private func rowBackground(isAlternate: Bool, isCurrentHour: Bool) -> Color {
        if isCurrentHour { return Theme.primary.opacity(0.07) }
        return isAlternate ? Theme.muted.opacity(0.25) : .clear
    }

    private func minuteChip(_ trip: TimetableTrip) -> some View {
        let isCancelled = cancelledTripIds.contains(trip.tripId)
        let vehicle = isCancelled ? nil : vehicleByTrip[trip.tripId]
        // A live GPS match arrives by trip id whatever the date, so only
        // today's board may read it as "this run is out there now".
        let isLive = day == .today && vehicle != nil
        let isWaiting = isLive && (journal[trip.tripId]?.isWaitingAtStart ?? false)
        let isNext = trip.tripId == nextTripId
        let isSelected = trip.tripId == selectedTripId
        let isPast = day == .today && trip.departureSec < nowSec && !isLive
        let minute = (trip.departureSec % 3600) / 60
        let style = ChipStyle(isCancelled: isCancelled, isWaiting: isWaiting, isLive: isLive, isSelected: isSelected, isNext: isNext, isPast: isPast)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)

        return Button {
            onSelectTrip(trip)
        } label: {
            Text(String(format: "%02d", minute))
                .font(Theme.mono(14, weight: .semibold))
                .strikethrough(isCancelled, pattern: .solid, color: Theme.destructive)
                .foregroundStyle(style.foreground)
                .frame(minWidth: 46, minHeight: 36)
                .padding(.horizontal, 6)
                .background(style.background, in: shape)
                .overlay(shape.strokeBorder(style.border, lineWidth: 1))
                .overlay(shape.strokeBorder(isCancelled && isSelected ? Theme.destructive : .clear, lineWidth: 2))
                .mvkShadow(isNext && !isLive && !isCancelled && !isSelected ? Theme.Shadow.sm : Theme.Shadow.Level(radius: 0, y: 0, opacity: 0))
                .overlay(alignment: .topTrailing) {
                    if let variant = trip.variant, !isCancelled {
                        Text(variant)
                            .font(Theme.sans(10, weight: .bold))
                            .foregroundStyle(isLive && !isWaiting ? Theme.primary : Theme.background)
                            .frame(minWidth: 16, minHeight: 16)
                            .padding(.horizontal, 2)
                            .background(isLive && !isWaiting ? Theme.primaryForeground : Theme.early, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .offset(x: 6, y: -6)
                    } else if trip.headsignDiffers && !isCancelled {
                        Circle()
                            .fill(isLive && !isWaiting ? Theme.primaryForeground : Theme.early)
                            .frame(width: 6, height: 6)
                            .padding(4)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if trip.deviates && trip.variant == nil && !isLive && !isCancelled {
                        Circle()
                            .fill(Theme.mutedForeground)
                            .frame(width: 4, height: 4)
                            .padding(4)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(ChipPressStyle())
        .id(trip.tripId)
        .accessibilityLabel(title(for: trip, isCancelled: isCancelled, liveVehicleId: vehicle?.id))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private struct ChipStyle {
        let foreground: Color
        let background: Color
        let border: Color

        init(isCancelled: Bool, isWaiting: Bool, isLive: Bool, isSelected: Bool, isNext: Bool, isPast: Bool) {
            if isCancelled {
                (foreground, background, border) = (Theme.destructive, Theme.destructive.opacity(0.12), Theme.destructive.opacity(0.6))
            } else if isWaiting {
                (foreground, background, border) = (Theme.foreground, Theme.primary.opacity(0.2), Theme.primary)
            } else if isLive {
                (foreground, background, border) = (Theme.primaryForeground, Theme.primary, Theme.primary)
            } else if isSelected {
                (foreground, background, border) = (Theme.foreground, Theme.primary.opacity(0.15), Theme.primary)
            } else if isNext {
                (foreground, background, border) = (Theme.foreground, Theme.card, Theme.primary)
            } else if isPast {
                (foreground, background, border) = (Theme.mutedForeground, Theme.muted.opacity(0.6), .clear)
            } else {
                (foreground, background, border) = (Theme.foreground, Theme.card, Theme.border)
            }
        }
    }

    /// The web's tooltip, read out by VoiceOver.
    private func title(for trip: TimetableTrip, isCancelled: Bool, liveVehicleId: String?) -> String {
        if isCancelled {
            return "\(trip.destinationName) TÖRÖLVE, ez a menet nem indul el"
        }
        let state = TripStatus.runState(
            TripStatus.RunInput(
                cancelled: false,
                hasLiveVehicle: liveVehicleId != nil,
                departureSec: trip.departureSec,
                arrivalSec: trip.arrivalSec,
                nowSec: nowSec,
                day: day,
                waitingAtStart: journal[trip.tripId]?.isWaitingAtStart ?? false
            )
        )
        let vehicleId = liveVehicleId ?? (TripStatus.showsJournalVehicle(state) ? journal[trip.tripId]?.vehicleId : nil)
        let variantLabel = trip.variant.flatMap { variantLabels[$0] }
        return [
            "\(trip.departure), \(trip.destinationName) érkezés \(trip.arrival)",
            variantLabel.flatMap { label in trip.variant.map { "\($0): \(label)" } },
            variantLabel == nil && trip.headsignDiffers
                ? "eltér a szokásos iránytól (\(directionHeadsign) helyett \(trip.headsign) felé)" : nil,
            TripStatus.runLabel(state, vehicleId: vehicleId),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    // MARK: - Derived

    private var tripIds: [String] { trips.map(\.tripId) }

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

    /// What the board scrolls to on open: the latest run out there now, or
    /// failing that the next one due.
    private var activeTripId: String? {
        guard day == .today else { return nil }
        let running = trips
            .filter { !cancelledTripIds.contains($0.tripId) && vehicleByTrip[$0.tripId] != nil }
            .max { $0.departureSec < $1.departureSec }
        return running?.tripId ?? nextTripId
    }
}

private struct ChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}
