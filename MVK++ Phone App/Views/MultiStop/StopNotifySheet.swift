//
//  StopNotifySheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// An alert for one stop: how early to be told, which routes count, and
/// congestion alerts — the web app's `StopNotifyDialog`.
struct StopNotifySheet: View {
    let stop: Stop
    let arrivals: [ArrivalItem]

    @ObservedObject private var notifications = NotificationCenterStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var threshold = String(NotificationCenterStore.defaultThresholdMin)
    @State private var routeShorts: [String] = []
    @State private var permissionDenied = false
    @State private var existed = false
    @FocusState private var thresholdFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Értesítés \(stop.name)")
                            .font(.system(size: 18, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Theme.foreground)
                        Text("Szólunk, amikor a busz a beállított időn belülre ér ehhez a megállóhoz lezárt telefonon is.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if permissionDenied {
                        ErrorNotice(message: "Az értesítések le vannak tiltva. Engedélyezd a Beállítások → Értesítések → MVK++ alatt.")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Riasztás ennyi percen belül")
                        TextField("", text: $threshold)
                            .keyboardType(.numberPad)
                            .focused($thresholdFocused)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 12)
                            .frame(width: 96, height: 40)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .strokeBorder(thresholdFocused ? Theme.ring : Theme.input, lineWidth: 1)
                            )
                            .onChange(of: threshold) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(2))
                                if digits != value { threshold = digits }
                            }
                            .accessibilityLabel("Riasztás ennyi percen belül")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Csak ezekre a járatokra")
                        Text("Ha egyet sem jelölsz be, bármelyik vonal jó.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedForeground)
                        if nearbyRoutes.isEmpty {
                            Text("Most nincs élő járat itt, amit ki lehetne választani.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.mutedForeground)
                        } else {
                            FlowLayout(spacing: 6, lineSpacing: 6) {
                                ForEach(nearbyRoutes, id: \.self, content: routeChip)
                            }
                            .padding(.top, 4)
                        }
                    }

                    TrafficAlertSwitch(stopId: stop.id, stopName: stop.name, routeShorts: routeShorts)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 8) {
                if existed {
                    Button(action: remove) {
                        Label("Értesítés kikapcsolása", systemImage: "bell.slash")
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.glass)
                    .tint(Theme.foreground)
                }
                Button {
                    Task { await save() }
                } label: {
                    Text("Mentés")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.primary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            await notifications.refreshAuthorization()
            permissionDenied = notifications.authorization == .denied
            if let existing = notifications.watch(stopId: stop.id) {
                existed = true
                threshold = String(existing.thresholdMin)
                routeShorts = existing.routeShorts ?? []
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.foreground)
    }

    private func routeChip(_ route: String) -> some View {
        let active = routeShorts.contains(route)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
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
                .frame(minHeight: 32)
                .background(active ? Theme.primary : Color.clear, in: shape)
                .overlay(shape.strokeBorder(active ? Theme.primary : Theme.border, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var nearbyRoutes: [String] {
        var seen = Set<String>()
        return arrivals.map(\.route).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func save() async {
        guard await notifications.requestPermission() else {
            permissionDenied = true
            return
        }
        let minutes = min(60, max(1, Int(threshold) ?? NotificationCenterStore.defaultThresholdMin))
        let previous = notifications.watch(stopId: stop.id)
        notifications.setWatch(
            NotifyWatch(
                stopId: stop.id,
                stopName: stop.name,
                thresholdMin: minutes,
                routeShorts: routeShorts.isEmpty ? nil : routeShorts,
                tripId: previous?.tripId,
                isDeparture: previous?.isDeparture,
                schedMin: previous?.schedMin
            )
        )
        notifications.scheduleAlarm(stopId: stop.id, stopName: stop.name, arrivals: arrivals)
        dismiss()
    }

    private func remove() {
        notifications.removeWatch(stopId: stop.id)
        notifications.cancelAlarm(stopId: stop.id)
        dismiss()
    }
}

/// Congestion alerts for a stop: told when traffic builds up ahead of a bus
/// heading here, with the expected extra time. Independent of the arrival
/// alert. The web app's `TrafficAlertSwitch`.
struct TrafficAlertSwitch: View {
    let stopId: String
    let stopName: String
    let routeShorts: [String]

    @ObservedObject private var alerts = AlertsStore.shared
    @State private var busy = false
    @State private var note: String?

    private static let slot = "traffic"

    var body: some View {
        let on = alerts.has(stopId: stopId, slot: Self.slot)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: "cone.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(TransitTone.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dugóriasztás")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text("Szólok, ha az ide tartó busz előtt beáll a forgalom\(routeShorts.isEmpty ? "" : " (\(routeShorts.joined(separator: ", ")))").")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Dugóriasztás ehhez a megállóhoz", isOn: Binding(
                    get: { on },
                    set: { next in Task { await toggle(next) } }
                ))
                .labelsHidden()
                .tint(Theme.primary)
                .disabled(busy)
            }
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func toggle(_ next: Bool) async {
        busy = true
        note = nil
        defer { busy = false }
        guard next else {
            await alerts.remove(stopId: stopId, slot: Self.slot)
            return
        }
        let result = await alerts.add(
            slot: Self.slot,
            kind: "traffic",
            stopId: stopId,
            stopName: stopName,
            routeShorts: routeShorts.isEmpty ? nil : routeShorts
        )
        if !result.ok {
            note = result.reason ?? "Nem sikerült bekapcsolni."
        } else if !result.push {
            note = result.noPushNote
        }
    }
}
