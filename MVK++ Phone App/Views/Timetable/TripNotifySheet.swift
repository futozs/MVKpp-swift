//
//  TripNotifySheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// An alarm pinned to one run at one stop — the web's `TripNotifyDialog`.
///
/// The recurring switch is the point: a trip id is only good for one day, so a
/// daily commute is pinned by the scheduled minute instead and keeps working
/// when tomorrow's runs get new ids.
struct TripNotifySheet: View {
    let stopId: String
    let stopName: String
    let tripId: String
    let routeShort: String
    /// The vehicle in sentences („3-as busz”, „IC vonat”).
    let vehicleLabel: String
    let isDeparture: Bool
    /// "HH:MM" for this run at this stop.
    let departureLabel: String
    /// The timetable's service day (`yyyy-MM-dd`): a one-off alarm is for
    /// that day only, since the trip id is another run on another day.
    let date: String

    @ObservedObject private var notifications = NotificationCenterStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var threshold = String(NotificationCenterStore.defaultThresholdMin)
    @State private var recurring = false
    @State private var permissionDenied = false
    @State private var existed = false
    @State private var pushStatus: PushStatus?
    @FocusState private var thresholdFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Értesítés: \(vehicleLabel), \(departureLabel)")
                        .font(Theme.sans(18, weight: .semibold))
                        .tracking(-0.45)
                        .padding(.trailing, 24)
                        .foregroundStyle(Theme.foreground)
                    Text(description)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if permissionDenied {
                    NotificationPermissionNote()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(isDeparture ? "Riasztás ennyi perccel indulás előtt" : "Riasztás ennyi perccel érkezés előtt")
                        .font(Theme.sans(14, weight: .medium))
                        .foregroundStyle(Theme.foreground)
                    TextField("", text: $threshold)
                        .keyboardType(.numberPad)
                        .focused($thresholdFocused)
                        .font(Theme.sans(14))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 12)
                        .frame(width: 96, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .strokeBorder(thresholdFocused ? Theme.ring : Theme.input, lineWidth: 1)
                        )
                        .onChange(of: threshold) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(2))
                            if digits != value { threshold = digits }
                        }
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ismétlődő, minden nap")
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                        Text("Nem csak erre az egy napra, hanem minden napra szól, amikor a \(vehicleLabel) \(departureLabel)-kor közlekedik innen. Ez kell a napi iskolabuszhoz/munkába járáshoz: egyszer állítod be, és nem kell újra minden alkalommal.")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Ismétlődő, minden nap", isOn: $recurring)
                        .labelsHidden()
                        .tint(Theme.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))

                if let pushStatus {
                    PushStatusBox(status: pushStatus)
                }

                VStack(spacing: 8) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text("Mentés")
                    }
                    .buttonStyle(.mvk(fullWidth: true))
                    if existed {
                        Button {
                            notifications.removeWatch(stopId: stopId)
                            notifications.cancelAlarm(stopId: stopId)
                            dismiss()
                        } label: {
                            Label("Értesítés kikapcsolása", systemImage: "bell.slash")
                        }
                        .buttonStyle(.mvk(.outline, fullWidth: true))
                    }
                }
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .mvkDialog()
        .sensoryFeedback(.success, trigger: existed)
        .task {
            await notifications.refreshAuthorization()
            permissionDenied = notifications.authorization == .denied
            if let existing = notifications.watch(stopId: stopId) {
                existed = true
                threshold = String(existing.thresholdMin)
                recurring = existing.schedMin != nil
            }
        }
    }

    private var description: String {
        let lead = isDeparture
            ? "Szólunk, mielőtt ez a menet elindul innen: \(stopName)"
            : "Szólunk, mielőtt ez a menet ideér: \(stopName)"
        return "\(lead), lezárt telefonon is, ha a push-regisztráció sikerül."
    }

    private func save() async {
        guard await notifications.requestPermission() else {
            permissionDenied = true
            return
        }
        PushService.shared.permissionGranted()
        let thresholdMin = min(60, max(1, Int(threshold) ?? NotificationCenterStore.defaultThresholdMin))
        notifications.setWatch(
            NotifyWatch(
                stopId: stopId,
                stopName: stopName,
                thresholdMin: thresholdMin,
                routeShorts: recurring ? [routeShort] : nil,
                tripId: recurring ? nil : tripId,
                isDeparture: isDeparture,
                schedMin: recurring ? Self.parseHourMinute(departureLabel) : nil,
                date: recurring ? nil : date
            )
        )
        guard let saved = notifications.watch(stopId: stopId) else { return }
        let result = await PushService.shared.register(saved)
        pushStatus = PushStatus(result)
        existed = true
    }

    /// "HH:MM" → minutes since midnight. GTFS times run past 24:00 for
    /// after-midnight service, so the result wraps.
    static func parseHourMinute(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1].prefix(2)),
              (0...27).contains(hour),
              (0...59).contains(minute)
        else { return nil }
        return (hour * 60 + minute) % 1440
    }
}
