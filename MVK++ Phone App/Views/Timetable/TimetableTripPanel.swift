//
//  TimetableTripPanel.swift
//  MVK++ Phone App
//

import SwiftUI

/// One run, under the board: its state, which vehicle has it, and either the
/// live progress rail or the stop list with alarms and measured arrivals.
/// The web's `TripDetail` panel.
struct TimetableTripPanel: View {
    let trip: TimetableTrip
    /// How this run differs (its route variant), if it does.
    let variantLabel: String?
    let stops: [TimetableStop]
    let routeShort: String
    let mode: TransitMode
    let vehicle: LiveVehicle?
    /// Pulled: not late, it does not run at all.
    let cancelled: Bool
    let dateYmd: String
    let journalEntry: TripJournalEntry?
    let nowSec: Int
    let day: DayRelation
    let maxHeight: CGFloat
    var onClose: () -> Void
    var onFocusTrip: (String, String?) -> Void

    @ObservedObject private var notifications = NotificationCenterStore.shared
    @StateObject private var actuals = TripActualsLoader()
    @State private var notifyTarget: NotifyTarget?

    private struct NotifyTarget: Identifiable {
        let stop: TimetableStop
        let isDeparture: Bool
        var id: String { stop.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.border).frame(height: 1)
            heading
            if cancelled {
                Text(day == .today
                     ? "Az MVK kihúzta ezt a menetet, ma nem közlekedik. Válassz másik indulást."
                     : "Az MVK kihúzta ezt a menetet, ezen a napon nem közlekedett.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.destructive.opacity(0.10))
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.destructive.opacity(0.25)).frame(height: 1) }
            } else if showRunSummary, let journalEntry {
                RunSummaryView(entry: journalEntry)
            }
            ScrollView {
                if let vehicle {
                    TripProgressRail(trip: trip, vehicleId: vehicle.id, stopNames: stops.map(\.name))
                        .id("\(trip.tripId)|\(vehicle.id)")
                } else {
                    stopList
                }
            }
        }
        .frame(maxHeight: maxHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.card)
        .mvkShadow(Theme.Shadow.xl)
        .sheet(item: $notifyTarget) { target in
            TripNotifySheet(
                stopId: target.stop.id,
                stopName: target.stop.name,
                tripId: trip.tripId,
                routeShort: routeShort,
                vehicleLabel: mode == .rail ? "\(routeShort) vonat" : "\(HungarianText.withSuffix(routeShort)) \(mode.noun)",
                isDeparture: target.isDeparture,
                departureLabel: stops.firstIndex(where: { $0.id == target.stop.id }).flatMap { index in
                    trip.times.indices.contains(index) ? trip.times[index] : nil
                } ?? trip.departure,
                date: ServiceClock.ymdToIso(dateYmd) ?? ServiceDay.isoToday()
            )
        }
        .task(id: actualsKey) {
            guard actualsEnabled else { return }
            await actuals.load(dateYmd: dateYmd, tripId: trip.tripId)
        }
    }

    // MARK: - Heading

    private var heading: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(trip.departure)
                .font(Theme.mono(20))
                .overlay {
                    if cancelled {
                        Rectangle().fill(Theme.destructive).frame(height: 2)
                    }
                }
                .foregroundStyle(cancelled ? Theme.destructive : Theme.foreground)

            VStack(alignment: .leading, spacing: 1) {
                Text(trip.destinationName)
                    .font(Theme.sans(12, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.mono(11, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let variantLabel, let variant = trip.variant {
                    HStack(spacing: 6) {
                        Text(variant)
                            .font(Theme.sans(10, weight: .bold))
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 16)
                            .background(Theme.early, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Text(variantLabel)
                            .font(Theme.sans(11.5, weight: .semibold))
                            .foregroundStyle(Theme.early)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
                if !cancelled, let statusLabel, vehicle != nil || pastVehicleId != nil {
                    Text(statusLabel)
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(state == .live ? Theme.live : Theme.mutedForeground)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.mvk(.ghost, size: .icon, height: 32))
            .accessibilityLabel("Menet részleteinek bezárása")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder
    private var trailing: some View {
        if cancelled {
            HStack(spacing: 4) {
                Image(systemName: "nosign").font(.system(size: 10, weight: .bold))
                Text("TÖRÖLVE").font(Theme.sans(11, weight: .bold)).tracking(0.5)
            }
            .foregroundStyle(Theme.destructive)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.destructive.opacity(0.5), lineWidth: 1))
        } else if let vehicle {
            Button {
                onFocusTrip(trip.tripId, vehicle.id)
            } label: {
                Label {
                    Text(TransitIds.displayVehicleId(vehicle.id, plate: vehicle.plate)).font(Theme.mono(12, weight: .medium))
                } icon: {
                    Image(systemName: "scope")
                }
            }
            .buttonStyle(.mvk(.primary, size: .small))
            .accessibilityLabel("\(TransitIds.displayVehicleId(vehicle.id, plate: vehicle.plate)) a térképen")
        } else if let pastVehicleId {
            Button {
                onFocusTrip(trip.tripId, pastVehicleId)
            } label: {
                Label {
                    Text(TransitIds.displayVehicleId(pastVehicleId)).font(Theme.mono(12, weight: .medium))
                } icon: {
                    Image(systemName: "bus")
                }
            }
            .buttonStyle(.mvk(.outline, size: .small))
            .accessibilityLabel("\(TransitIds.vehicleIdTitle(pastVehicleId)) teljesítette ezt a menetet. Megnézem, hol jár most")
        } else if let statusLabel {
            Text(statusLabel)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
                .fixedSize()
        }
    }

    // MARK: - Stops

    private var stopList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !cancelled && state == .scheduled {
                Text("Koppints egy megálló csengőjére, hogy szóljunk, mielőtt a busz odaér.")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            VStack(spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    if trip.times.indices.contains(index), let time = trip.times[index] {
                        stopRow(stop: stop, time: time, index: index)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Only the first stop with an alarm for this run rings (web `watchedStopIndex`).
    private var watchedStopIndex: Int? {
        stops.firstIndex { notifications.watch(stopId: $0.id)?.tripId == trip.tripId }
    }

    private func stopRow(stop: TimetableStop, time: String, index: Int) -> some View {
        let watching = index == watchedStopIndex
        let actual = actuals.byStop[stop.id]
        return HStack(spacing: 8) {
            Text(stop.name)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text(time)
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                if let actual {
                    Text("\(actual.estimated ? "~" : "")\(Self.clockText(actual.arr)) (\(Self.delayText(actual.delay)))")
                        .font(Theme.mono(11, weight: .regular))
                        .foregroundStyle(actual.delay > 180 ? Theme.late : actual.delay < -60 ? Theme.early : Theme.ontime)
                        .accessibilityHint(actual.estimated ? "Becsült beérkezés (a jármű a végállomás előtt elnémult)" : "Mért érkezés")
                }
                if !cancelled && state == .scheduled {
                    Button {
                        notifyTarget = NotifyTarget(stop: stop, isDeparture: index == 0)
                    } label: {
                        Image(systemName: watching ? "bell.and.waves.left.and.right" : "bell")
                            .font(.system(size: 12))
                            .foregroundStyle(watching ? Theme.primary : Theme.mutedForeground)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TimetablePressStyle(cornerRadius: Theme.Radius.md))
                    .accessibilityLabel("Értesítés beállítása \(stop.name)")
                }
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.4)).frame(height: 1) }
    }

    static func clockText(_ unix: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.timeZone = ServiceClock.timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: unix))
    }

    static func delayText(_ sec: Int) -> String {
        if abs(sec) < 45 { return "pontos" }
        let minutes = abs(sec) / 60
        let seconds = String(format: "%02d", abs(sec) % 60)
        return "\(sec > 0 ? "+" : "−")\(minutes):\(seconds)"
    }

    // MARK: - Derived

    private var state: TripRunState {
        TripStatus.runState(
            TripStatus.RunInput(
                cancelled: cancelled,
                hasLiveVehicle: vehicle != nil,
                departureSec: trip.departureSec,
                arrivalSec: trip.arrivalSec,
                nowSec: nowSec,
                day: day,
                waitingAtStart: journalEntry?.isWaitingAtStart ?? false
            )
        )
    }

    /// The journal keeps the vehicle after the run; by then the bus is
    /// elsewhere, but "which bus took this one" is exactly the question.
    private var pastVehicleId: String? {
        TripStatus.showsJournalVehicle(state) ? journalEntry?.vehicleId : nil
    }

    private var showRunSummary: Bool {
        !cancelled && journalEntry != nil && state != .scheduled
    }

    private var statusLabel: String? {
        TripStatus.runLabel(state, vehicleId: showRunSummary ? nil : pastVehicleId)
    }

    private var subtitle: String {
        var text = "érkezés \(trip.arrival) · \(trip.stopCount) megálló"
        if variantLabel == nil && trip.deviates { text += " · betérő" }
        if variantLabel == nil && trip.headsignDiffers { text += " · eltérő célállomás" }
        return text
    }

    private var actualsEnabled: Bool { !dateYmd.isEmpty && !cancelled && state != .scheduled }

    /// Refetched as the journal moves on, so a running trip fills in stop by stop.
    private var actualsKey: String {
        "\(dateYmd)|\(trip.tripId)|\(actualsEnabled)|\(journalEntry?.stopsSeen ?? 0)|\(journalEntry?.status ?? "")"
    }
}

private struct ChipPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.fastAnimation, value: configuration.isPressed)
    }
}
