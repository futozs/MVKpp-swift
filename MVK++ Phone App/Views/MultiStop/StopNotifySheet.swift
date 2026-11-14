//
//  StopNotifySheet.swift
//  MVK++ Phone App
//

import SwiftUI
import UIKit

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
    @State private var pushStatus: PushStatus?
    @FocusState private var thresholdFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Értesítés: \(stop.name)")
                            .font(Theme.sans(18, weight: .semibold))
                            .tracking(-0.45)
                            .padding(.trailing, 24)
                            .foregroundStyle(Theme.foreground)
                        Text("Szólunk, amikor a busz a beállított időn belülre ér ehhez a megállóhoz, lezárt telefonon is, ha a push-regisztráció sikerül.")
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if permissionDenied {
                        NotificationPermissionNote()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Riasztás ennyi percen belül")
                        TextField("", text: $threshold)
                            .keyboardType(.numberPad)
                            .focused($thresholdFocused)
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 12)
                            .frame(width: 96, height: 36)
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
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.mutedForeground)
                        if nearbyRoutes.isEmpty {
                            Text("Most nincs élő járat itt, amit ki lehetne választani.")
                                .font(Theme.sans(11))
                                .foregroundStyle(Theme.mutedForeground)
                        } else {
                            FlowLayout(spacing: 6, lineSpacing: 6) {
                                ForEach(nearbyRoutes, id: \.self, content: routeChip)
                            }
                            .padding(.top, 4)
                        }
                    }

                    TrafficAlertSwitch(stopId: stop.id, stopName: stop.name, routeShorts: routeShorts)

                    if let pushStatus {
                        PushStatusBox(status: pushStatus)
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 8) {
                Button {
                    Task { await save() }
                } label: {
                    Text("Mentés")
                }
                .buttonStyle(.mvk(fullWidth: true))
                if existed {
                    Button(action: remove) {
                        Label("Értesítés kikapcsolása", systemImage: "bell.slash")
                    }
                    .buttonStyle(.mvk(.outline, fullWidth: true))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .mvkDialog()
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
            .font(Theme.sans(14, weight: .medium))
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
        PushService.shared.permissionGranted()
        // A watch pinned to a run (from the Menetrend, or daily at one time)
        // stays pinned; otherwise saving here would widen it to any bus.
        let previous = notifications.watch(stopId: stop.id)
        notifications.setWatch(
            NotifyWatch(
                stopId: stop.id,
                stopName: stop.name,
                thresholdMin: minutes,
                routeShorts: routeShorts.isEmpty ? nil : routeShorts,
                tripId: previous?.tripId,
                isDeparture: previous?.isDeparture,
                schedMin: previous?.schedMin,
                date: previous?.date
            )
        )
        existed = true
        guard let saved = notifications.watch(stopId: stop.id) else { return }
        let result = await PushService.shared.register(saved)
        pushStatus = PushStatus(result)
        notifications.scheduleAlarm(stopId: stop.id, stopName: stop.name, arrivals: arrivals)
    }

    private func remove() {
        notifications.removeWatch(stopId: stop.id)
        notifications.cancelAlarm(stopId: stop.id)
        dismiss()
    }
}

/// The outcome of a notify sheet's push registration.
struct PushStatus: Equatable {
    let ok: Bool
    let reason: String?

    init(_ diagnostic: PushService.Diagnostic) {
        ok = diagnostic.ok
        reason = diagnostic.reason
    }
}

/// „Lezárt telefonos (push) értesítés”: whether the server took the watch, so
/// the rider knows if it also comes with the phone locked.
struct PushStatusBox: View {
    let status: PushStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lezárt telefonos (push) értesítés")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
            if status.ok {
                Label("Sikeresen regisztrálva a szerveren.", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.ontime)
            } else {
                Label(status.reason ?? "Nem sikerült regisztrálni a szerveren.", systemImage: "xmark.circle")
                    .foregroundStyle(Theme.destructive)
            }
        }
        .font(.system(size: 11))
        .labelStyle(StatusLabelStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private struct StatusLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                configuration.icon
                configuration.title.fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Why no alarm can be set: iOS has notifications switched off for the app.
/// Shared by the stop and trip notify sheets (web `PermissionNote`).
struct NotificationPermissionNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ErrorNotice(message: "Az iOS letiltotta az értesítéseket ehhez az apphoz. Engedélyezd a Beállítások appban, majd próbáld újra.")
            Button("Beállítások megnyitása") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.mvk(.outline, size: .small))
        }
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
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text("Szólok, ha az ide tartó busz előtt beáll a forgalom\(routeShorts.isEmpty ? "" : " (\(routeShorts.joined(separator: ", ")))").")
                        .font(Theme.sans(11))
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
                    .font(Theme.sans(11))
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
