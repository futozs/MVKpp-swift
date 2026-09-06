//
//  TripDetailSheet.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

/// Everything about one departure: whether it is running, which vehicle has
/// it, where that vehicle is, and — the part that matters most — what time it
/// will *actually* reach each stop.
///
/// The status band is pinned. Scrolling down a nineteen-stop run must never
/// hide the one fact the rider is reading the list for: how late it is.
struct TripDetailSheet: View {
    let trip: TimetableTrip
    let stops: [TimetableStop]
    let routeShort: String
    let vehicle: LiveVehicle?
    let isCancelled: Bool
    let journalEntry: TripJournalEntry?
    let nowSec: Int
    let day: DayRelation
    var onFocusTrip: (String, String?) -> Void

    @ObservedObject private var notifications = NotificationCenterStore.shared
    @StateObject private var progress = TripProgressModel()
    @Environment(\.dismiss) private var dismiss

    @State private var notifyTarget: NotifyTarget?

    private struct NotifyTarget: Identifiable {
        let stop: TimetableStop
        let isDeparture: Bool
        let timeLabel: String
        var id: String { stop.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        stopList
                    } header: {
                        statusBand
                    }
                }
            }
            .background(AppBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) { heading }
            .sheet(item: $notifyTarget) { target in
                TripNotifySheet(
                    stopId: target.stop.id,
                    stopName: target.stop.name,
                    tripId: trip.tripId,
                    routeShort: routeShort,
                    isDeparture: target.isDeparture,
                    timeLabel: target.timeLabel
                )
                .presentationDetents([.medium])
            }
            .task(id: vehicleKey) {
                guard let vehicle, !isCancelled else { return }
                await progress.start(tripId: trip.tripId, vehicleId: vehicle.id)
            }
            .onDisappear { progress.stop() }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Heading

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(trip.departure)
                .font(Theme.mono(24))
                .strikethrough(isCancelled, color: Theme.destructive)
                .foregroundStyle(isCancelled ? Theme.destructive : Theme.foreground)

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.destinationName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.mono(11, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.bar)
    }

    // MARK: - Pinned status band

    private var statusBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isCancelled {
                Label("Törölve — ez a menet nem indul el", systemImage: "nosign")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.destructive)
            } else {
                HStack(spacing: 10) {
                    if let vehicleId = shownVehicleId {
                        HStack(spacing: 5) {
                            Image(systemName: "bus.fill").font(.system(size: 11))
                            Text(vehicleId).font(Theme.mono(13))
                        }
                        .foregroundStyle(Theme.primary)
                    }

                    if let statusLabel {
                        Text(statusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(state == .live ? Theme.live : Theme.mutedForeground)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    DelayBar(delaySec: deviationSec, showLabel: false)
                    Text(DelayFormat.sentence(deviationSec))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DelayFormat.tone(deviationSec))
                }

                if let nextStopName = progress.progress?.nextStop?.name {
                    Text("következő: \(nextStopName)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    // MARK: - Stops

    private var stopList: some View {
        VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                // A nil entry means this run skips the stop entirely.
                if let time = time(at: index) {
                    stopRow(stop: stop, time: time, index: index)
                }
            }
        }
        .padding(.bottom, 28)
    }

    private func stopRow(stop: TimetableStop, time: String, index: Int) -> some View {
        let isWatchingThisStop = notifications.watch(stopId: stop.id)?.tripId == trip.tripId
        let shifted = ScheduleTime.shifted(time, bySeconds: deviationSec)
        let passed = progress.progress?.segmentIndex.map { index <= $0 } ?? false
        let isNext = progress.progress?.segmentIndex.map { index == $0 + 1 } ?? false

        return HStack(spacing: 10) {
            // The rail: filled behind the vehicle, hollow ahead of it.
            Circle()
                .fill(passed ? Theme.primary : Theme.background)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(passed || isNext ? Theme.primary : Theme.border, lineWidth: 2))
                .frame(width: 18)

            Text(stop.name)
                .font(.system(size: 13, weight: isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? Theme.foreground : Theme.mutedForeground)
                .lineLimit(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                if let shifted {
                    // The time it will really be, with the printed one kept
                    // underneath so the rider can see what changed.
                    Text(shifted)
                        .font(Theme.mono(14))
                        .foregroundStyle(DelayFormat.tone(deviationSec))
                    Text(time)
                        .font(Theme.mono(10, weight: .regular))
                        .strikethrough()
                        .foregroundStyle(Theme.mutedForeground)
                } else {
                    Text(time)
                        .font(Theme.mono(14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                }
            }

            if !isCancelled && state == .scheduled {
                Button {
                    notifyTarget = NotifyTarget(stop: stop, isDeparture: index == 0, timeLabel: time)
                } label: {
                    Image(systemName: isWatchingThisStop ? "bell.badge.fill" : "bell")
                        .font(.system(size: 13))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isWatchingThisStop ? Theme.primary : Theme.mutedForeground)
                .accessibilityLabel("Értesítés — \(stop.name)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isNext ? Theme.primary.opacity(0.07) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1).padding(.leading, 44)
        }
    }

    private func time(at index: Int) -> String? {
        guard trip.times.indices.contains(index) else { return nil }
        return trip.times[index]
    }

    // MARK: - Derived state

    private var vehicleKey: String { "\(trip.tripId)|\(vehicle?.id ?? "")" }

    /// Live deviation while the run is out there; the journal's own figure
    /// once it has finished.
    private var deviationSec: Int? {
        progress.progress?.scheduleDeviationSec
            ?? (TripStatus.showsJournalVehicle(state) ? journalEntry?.startDelaySec : nil)
    }

    private var state: TripRunState {
        TripStatus.runState(
            TripStatus.RunInput(
                cancelled: isCancelled,
                hasLiveVehicle: vehicle != nil,
                departureSec: trip.departureSec,
                arrivalSec: trip.arrivalSec,
                nowSec: nowSec,
                day: day
            )
        )
    }

    /// The journal keeps the vehicle assignment after a run ends — by then the
    /// live feed has moved that bus onto its next run, but "which bus took
    /// this one" is still the rider's question.
    private var shownVehicleId: String? {
        vehicle?.id ?? (TripStatus.showsJournalVehicle(state) ? journalEntry?.vehicleId : nil)
    }

    private var statusLabel: String? {
        TripStatus.runLabel(state, vehicleId: nil)
    }

    private var subtitle: String {
        var parts = ["érkezés \(arrivalText)", "\(trip.stopCount) megálló"]
        if trip.deviates { parts.append("betérő") }
        if trip.headsignDiffers { parts.append("eltérő célállomás") }
        return parts.joined(separator: " · ")
    }

    private var arrivalText: String {
        ScheduleTime.shifted(trip.arrival, bySeconds: deviationSec) ?? trip.arrival
    }
}
