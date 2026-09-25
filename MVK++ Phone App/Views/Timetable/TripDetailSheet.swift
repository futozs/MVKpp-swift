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
                stopList
            }
            .background(AppBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            // `heading` and `statusBand` are pinned together as one inset
            // rather than through `LazyVStack(pinnedViews:)` — a pinned
            // section header whose height depends on conditional content
            // (cancelled / run summary / live vs. finished) leaves a stale
            // gap behind after the sheet has been presented many times, since
            // its cached header height doesn't always get invalidated. A
            // plain safeAreaInset re-measures every time, so it can't drift.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    heading
                    statusBand
                }
            }
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

            headingTrailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.bar)
    }

    /// The one piece of chrome the rider actually reaches for: jump to this
    /// bus on the map. Live shows a solid button (it can be focused right
    /// now); a finished or running-but-unmatched run still names the vehicle
    /// that took it, because "which bus was that?" doesn't stop being useful
    /// once the run is over.
    @ViewBuilder
    private var headingTrailing: some View {
        if isCancelled {
            Label("Törölve", systemImage: "nosign")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.destructive)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .strokeBorder(Theme.destructive.opacity(0.4), lineWidth: 1)
                )
        } else if let vehicle {
            Button {
                onFocusTrip(trip.tripId, vehicle.id)
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "scope").font(.system(size: 11, weight: .semibold))
                    Text(vehicle.id).font(Theme.mono(12, weight: .bold))
                }
                .foregroundStyle(Theme.primaryForeground)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(vehicle.id) a térképen")
        } else if let shownVehicleId {
            Button {
                onFocusTrip(trip.tripId, shownVehicleId)
                dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bus.fill").font(.system(size: 11))
                    Text(shownVehicleId).font(Theme.mono(12, weight: .semibold))
                }
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(shownVehicleId) \(state == .finished ? "vitte" : "viszi") — megnézem a térképen")
        }
    }

    // MARK: - Pinned status band

    /// Only the settled facts about this run: its status word and — once the
    /// gateway has a journal entry for it — what actually happened at
    /// departure and arrival. This stays pinned because it doesn't change as
    /// the rider scrolls through stops.
    private var statusBand: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCancelled {
                Label("Törölve — ez a menet nem indul el", systemImage: "nosign")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.destructive)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            } else {
                if let statusLabel {
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state == .live ? Theme.live : Theme.mutedForeground)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, showRunSummary ? 6 : 10)
                }

                if showRunSummary, let journalEntry {
                    RunSummaryView(entry: journalEntry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    /// The journal is what actually happened; showing it needs neither a
    /// live vehicle nor the run being over — a run in progress that has
    /// already logged its start delay is worth surfacing too.
    private var showRunSummary: Bool {
        !isCancelled && journalEntry != nil && state != .scheduled
    }

    // MARK: - Live progress

    /// The moving part: current position, next stop, live schedule
    /// deviation. Scrolls away with the stop list instead of staying pinned,
    /// because unlike the status band this keeps changing underneath the
    /// rider as the bus moves.
    @ViewBuilder
    private var liveProgressRow: some View {
        if !isCancelled, vehicle != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let progressData = progress.progress {
                    HStack(spacing: 8) {
                        if let vehicleId = shownVehicleId {
                            Text(vehicleId)
                                .font(Theme.mono(12, weight: .bold))
                                .foregroundStyle(Theme.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }

                        Text(progressSubtitle(progressData))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }

                    if let dev = progressData.scheduleDeviationSec, DelayFormat.state(dev) != .unknown {
                        HStack(spacing: 8) {
                            DelayBar(delaySec: dev, showLabel: false)
                            Text(DelayFormat.sentence(dev))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DelayFormat.tone(dev))
                        }
                    }
                } else {
                    Text("Erre a menetre még nem jelentkezett be jármű.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    private func progressSubtitle(_ data: TripProgressResponse) -> String {
        var text = data.nextStop.map { "következő: \($0.name)" } ?? "útközben"
        if let speed = data.vehicle?.speed {
            text += " · \(Int((speed * 3.6).rounded())) km/h"
        }
        return text
    }

    // MARK: - Stops

    private var stopList: some View {
        VStack(spacing: 0) {
            liveProgressRow

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

    /// Live schedule deviation, straight from the vehicle feed. Deliberately
    /// not backed by the journal's start delay — that number describes one
    /// moment (departure), not the whole run, so stretching it across every
    /// later stop would misstate arrivals. The journal's own start/end
    /// figures are shown as-is in `RunSummaryView` instead.
    private var deviationSec: Int? {
        progress.progress?.scheduleDeviationSec
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
