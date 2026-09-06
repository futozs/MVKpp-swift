//
//  TripNotifySheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// An alarm pinned to one departure at one stop.
///
/// The recurring switch is the point of this screen: a trip ID is only good
/// for today, so a daily commute is pinned by the *scheduled minute* instead,
/// and keeps working tomorrow when the operator issues new IDs.
struct TripNotifySheet: View {
    let stopId: String
    let stopName: String
    let tripId: String
    let routeShort: String
    let isDeparture: Bool
    /// "HH:MM" for this run at this stop.
    let timeLabel: String

    @ObservedObject private var notifications = NotificationCenterStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var thresholdMin = NotificationCenterStore.defaultThresholdMin
    @State private var isRecurring = false
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                if permissionDenied {
                    Section {
                        ErrorNotice(message: "Az értesítések le vannak tiltva — engedélyezd a rendszerbeállításokban.")
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Stepper(value: $thresholdMin, in: 1...60) {
                        HStack {
                            Text(isDeparture ? "Indulás előtt" : "Érkezés előtt")
                            Spacer()
                            Text("\(thresholdMin) perccel")
                                .font(Theme.mono(14, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }
                    }
                } header: {
                    Text(stopName)
                }
                .listRowBackground(Theme.card)

                Section {
                    Toggle("Ismétlődő — minden nap", isOn: $isRecurring)
                        .tint(Theme.primary)
                } footer: {
                    Text("Minden nap, nem csak ma.")
                }
                .listRowBackground(Theme.card)

                if notifications.hasWatch(stopId: stopId) {
                    Section {
                        Button(role: .destructive) {
                            notifications.removeWatch(stopId: stopId)
                            notifications.cancelAlarm(stopId: stopId)
                            dismiss()
                        } label: {
                            Label("Értesítés kikapcsolása", systemImage: "bell.slash")
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .mvkBackground()
            .navigationTitle("\(HungarianText.withSuffix(routeShort)) · \(timeLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") { Task { await save() } }
                }
            }
            .task {
                await notifications.refreshAuthorization()
                permissionDenied = notifications.authorization == .denied
                if let existing = notifications.watch(stopId: stopId) {
                    thresholdMin = existing.thresholdMin
                    isRecurring = existing.schedMin != nil
                }
            }
        }
    }

    private func save() async {
        let granted = await notifications.requestPermission()
        guard granted else {
            permissionDenied = true
            return
        }

        notifications.setWatch(
            NotifyWatch(
                stopId: stopId,
                stopName: stopName,
                thresholdMin: min(60, max(1, thresholdMin)),
                // A recurring watch matches by route + scheduled minute; a
                // one-off pins the exact trip.
                routeShorts: isRecurring ? [routeShort] : nil,
                tripId: isRecurring ? nil : tripId,
                isDeparture: isDeparture,
                schedMin: isRecurring ? Self.parseHourMinute(timeLabel) : nil
            )
        )
        dismiss()
    }

    /// "HH:MM" → minutes since midnight. GTFS times can run past 24:00 for
    /// after-midnight service, so the result wraps.
    static func parseHourMinute(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...27).contains(hour),
              (0...59).contains(minute)
        else { return nil }
        return (hour * 60 + minute) % 1440
    }
}
