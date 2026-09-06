//
//  StopNotifySheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// Set up an alert for one stop: how early to be told, and which routes count.
struct StopNotifySheet: View {
    let stop: Stop
    let arrivals: [ArrivalItem]

    @ObservedObject private var notifications = NotificationCenterStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var thresholdMin = NotificationCenterStore.defaultThresholdMin
    @State private var routeShorts: [String] = []
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
                            Text("Riasztás")
                            Spacer()
                            Text("\(thresholdMin) percen belül")
                                .font(Theme.mono(14, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }
                    }
                } header: {
                    Text("Mikor szóljunk")
                }
                .listRowBackground(Theme.card)

                Section {
                    if nearbyRoutes.isEmpty {
                        Text("Most nincs élő járat itt, amit ki lehetne választani.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.mutedForeground)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(nearbyRoutes, id: \.self) { route in
                                routeChip(route)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Csak ezekre a járatokra")
                } footer: {
                    Text("Ha egyet sem jelölsz be, bármelyik jó.")
                }
                .listRowBackground(Theme.card)

                if notifications.hasWatch(stopId: stop.id) {
                    Section {
                        Button(role: .destructive) {
                            notifications.removeWatch(stopId: stop.id)
                            notifications.cancelAlarm(stopId: stop.id)
                            dismiss()
                        } label: {
                            Label("Értesítés kikapcsolása", systemImage: "bell.slash")
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .mvkBackground()
            .navigationTitle("Értesítés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") { Task { await save() } }
                }
            }
            .safeAreaInset(edge: .top) {
                Text(stop.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
            .task {
                await notifications.refreshAuthorization()
                permissionDenied = notifications.authorization == .denied
                if let existing = notifications.watch(stopId: stop.id) {
                    thresholdMin = existing.thresholdMin
                    routeShorts = existing.routeShorts ?? []
                }
            }
        }
    }

    private func routeChip(_ route: String) -> some View {
        let active = routeShorts.contains(route)
        return Button {
            if let index = routeShorts.firstIndex(of: route) {
                routeShorts.remove(at: index)
            } else {
                routeShorts.append(route)
            }
        } label: {
            Text(route)
                .font(Theme.mono(12))
                .foregroundStyle(active ? Theme.primaryForeground : Theme.mutedForeground)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    active ? Theme.primary : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .strokeBorder(active ? Theme.primary : Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private var nearbyRoutes: [String] {
        var seen = Set<String>()
        return arrivals.map(\.route).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func save() async {
        let granted = await notifications.requestPermission()
        guard granted else {
            permissionDenied = true
            return
        }

        notifications.setWatch(
            NotifyWatch(
                stopId: stop.id,
                stopName: stop.name,
                thresholdMin: min(60, max(1, thresholdMin)),
                routeShorts: routeShorts.isEmpty ? nil : routeShorts
            )
        )
        dismiss()
    }
}
