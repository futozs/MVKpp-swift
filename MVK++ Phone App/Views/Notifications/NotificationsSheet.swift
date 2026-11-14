//
//  NotificationsSheet.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI
import UIKit

/// Értesítések (web `NotificationsModal`): permission and the main switch,
/// do-not-disturb, the special alerts, the stop watches with editing, and the
/// device's delivery log.
struct NotificationsSheet: View {
    @ObservedObject private var center = NotificationCenterStore.shared
    @ObservedObject private var alerts = AlertsStore.shared
    @ObservedObject private var push = PushService.shared

    @State private var enabledSaving = false
    @State private var enabledNote: String?
    @State private var dndSaving = false
    @State private var dndNote: String?
    @State private var editingId: String?
    @State private var editThreshold = NotificationCenterStore.defaultThresholdMin
    @State private var editRoutes = ""
    @State private var editBusy = false
    @State private var deliveries: [PushService.Delivery] = []

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(icon: "bell", title: "Értesítések", subtitle: "Mikor és milyen buszokról kapj figyelmeztetést.")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    permissionRow
                    dndBox
                    AlertList()
                    watchList
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                DeliveryLog(rows: deliveries)
            }
        }
        .presentationDetents([.large])
        .task {
            await center.refreshAuthorization()
            alerts.prune()
            deliveries = await push.deliveries()
        }
    }

    // MARK: - Permission

    private var permissionText: String {
        switch center.authorization {
        case .authorized, .provisional, .ephemeral: return "Az iOS engedélyezte."
        case .denied: return "Az iOS letiltotta. A Beállítások appban engedélyezheted újra."
        default: return "Még nem engedélyezted."
        }
    }

    private var permissionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Értesítések ezen az eszközön")
                        .font(Theme.sans(14, weight: .semibold))
                    Text(permissionText)
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                }
                Spacer(minLength: 8)
                if center.authorization == .denied {
                    Button("Beállítások") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.mvk(.outline, size: .small))
                } else if !center.isAuthorized {
                    Button("Engedélyezés") {
                        Task {
                            if await center.requestPermission() { push.permissionGranted() }
                        }
                    }
                    .buttonStyle(.mvk(.outline, size: .small))
                } else {
                    MVKSwitch(isOn: Binding(get: { center.settings.enabled }, set: { applyEnabled($0) }), label: "Értesítések ezen az eszközön")
                }
            }
            if enabledSaving {
                Text("Mentés…").font(Theme.sans(11)).foregroundStyle(Theme.mutedForeground)
            } else if let enabledNote {
                Text(enabledNote).font(Theme.sans(11)).foregroundStyle(Theme.early)
            }
        }
    }

    private func applyEnabled(_ enabled: Bool) {
        center.settings.enabled = enabled
        enabledSaving = true
        enabledNote = nil
        Task {
            let result = await push.setEnabled(enabled)
            enabledSaving = false
            if !result.ok, !(result.reason ?? "").contains("feliratkozás") {
                enabledNote = result.reason ?? "Nem sikerült menteni a szerveren."
            }
        }
    }

    // MARK: - Do not disturb

    private var dndBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text("Ne zavarj").font(Theme.sans(14, weight: .semibold))
                } icon: {
                    Image(systemName: "moon.stars").font(.system(size: 13)).foregroundStyle(Theme.primary)
                }
                .labelStyle(.titleAndIcon)
                Spacer()
                MVKSwitch(isOn: Binding(get: { center.settings.dndEnabled }, set: { value in applyDnd { $0.dndEnabled = value } }), label: "Ne zavarj időszak")
                    .disabled(!center.settings.enabled)
            }
            if center.settings.dndEnabled {
                HStack(spacing: 8) {
                    timeField("Ettől", minutes: center.settings.dndStartMin) { value in applyDnd { $0.dndStartMin = value } }
                    timeField("Eddig", minutes: center.settings.dndEndMin) { value in applyDnd { $0.dndEndMin = value } }
                }
            } else {
                Text("Ilyenkor egyetlen értesítés sem érkezik: sem a nyitott appban, sem lezárt telefonra.")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if dndSaving {
                Text("Mentés…").font(Theme.sans(11)).foregroundStyle(Theme.mutedForeground)
            } else if let dndNote {
                Text(dndNote).font(Theme.sans(11)).foregroundStyle(Theme.early)
            }
        }
        .padding(14)
        .background(Theme.muted.opacity(0.3), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .opacity(center.settings.enabled ? 1 : 0.5)
    }

    private func timeField(_ label: String, minutes: Int, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.sans(11)).foregroundStyle(Theme.mutedForeground)
            DatePicker(label, selection: Binding(
                get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    onChange(((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) % 1440)
                }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "hu_HU"))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyDnd(_ change: (inout NotificationSettings) -> Void) {
        var next = center.settings
        change(&next)
        center.settings = next
        dndSaving = true
        dndNote = nil
        Task {
            let result = await push.setDnd(enabled: next.dndEnabled, startMin: next.dndStartMin, endMin: next.dndEndMin)
            dndSaving = false
            if !result.ok {
                dndNote = (result.reason ?? "").contains("feliratkozás")
                    ? "A nyitott appban már érvényes, a lezárt telefonra érkező push-hoz még nincs feliratkozás egyetlen megállóra sem."
                    : (result.reason ?? "Nem sikerült menteni a szerveren.")
            }
        }
    }

    // MARK: - Stop watches

    private var sortedWatches: [NotifyWatch] {
        center.watches.values.sorted { $0.stopName.localizedCompare($1.stopName) == .orderedAscending }
    }

    private static func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    private static func label(_ watch: NotifyWatch) -> String {
        if watch.tripId != nil { return "egy konkrét indulás" }
        if let sched = watch.schedMin { return "napi \(time(sched))-kor" }
        if let routes = watch.routeShorts, !routes.isEmpty { return routes.joined(separator: ", ") + " járat" }
        return "bármelyik járat"
    }

    private var watchList: some View {
        let watches = sortedWatches
        return VStack(alignment: .leading, spacing: 8) {
            CapsLabel("Aktív figyelések (\(watches.count))")
            if watches.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash").font(.system(size: 13))
                    Text("Egyetlen megállóra vagy indulásra sincs beállítva figyelés. A menetrend vagy egy megálló kártyáján a csengő ikonnal adhatsz hozzá.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.sans(12))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(watches.enumerated()), id: \.element.stopId) { index, watch in
                        if index > 0 { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
                        if editingId == watch.stopId { editor(watch) } else { row(watch) }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
        }
    }

    private func row(_ watch: NotifyWatch) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(watch.stopName)
                    .font(Theme.sans(12, weight: .semibold))
                    .lineLimit(1)
                Text("\(Self.label(watch)) · \(watch.thresholdMin) percen belül\(watch.pushRegistered == true ? " · lezárt telefonra is" : "")")
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            iconButton("pencil", label: "Figyelés szerkesztése \(watch.stopName)") {
                editingId = watch.stopId
                editThreshold = watch.thresholdMin
                editRoutes = (watch.routeShorts ?? []).joined(separator: ", ")
            }
            iconButton("trash", label: "Figyelés törlése \(watch.stopName)", destructive: true) {
                center.removeWatch(stopId: watch.stopId)
                center.cancelAlarm(stopId: watch.stopId)
                if editingId == watch.stopId { editingId = nil }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func iconButton(_ icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(destructive ? Theme.destructive.opacity(0.85) : Theme.mutedForeground)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func editor(_ watch: NotifyWatch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(watch.stopName).font(Theme.sans(12, weight: .semibold)).lineLimit(1)
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Percen belül").font(Theme.sans(11, weight: .medium))
                    TextField("", value: $editThreshold, format: .number)
                        .textFieldStyle(MVKTextFieldStyle())
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Járatok (üres = bármelyik)").font(Theme.sans(11, weight: .medium))
                    TextField("", text: $editRoutes, prompt: Text("pl. 1, 2A").foregroundStyle(Theme.mutedForeground))
                        .textFieldStyle(MVKTextFieldStyle())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button { editingId = nil } label: { Label("Mégse", systemImage: "xmark") }
                    .buttonStyle(.mvk(.ghost, size: .small))
                Button { save(watch) } label: { Label("Mentés", systemImage: "checkmark") }
                    .buttonStyle(.mvk(.primary, size: .small))
            }
            .disabled(editBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// The edited watch is saved; the push mirror re-registers it on the server.
    private func save(_ watch: NotifyWatch) {
        editBusy = true
        var next = watch
        next.thresholdMin = max(1, min(60, editThreshold == 0 ? NotificationCenterStore.defaultThresholdMin : editThreshold))
        let routes = editRoutes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        next.routeShorts = routes.isEmpty ? nil : routes
        center.setWatch(next)
        editBusy = false
        editingId = nil
    }
}

/// The special alerts ("indulj most", traffic, transfer) — switched off here.
struct AlertList: View {
    @ObservedObject private var alerts = AlertsStore.shared

    private static let dayNames = ["", "hétfő", "kedd", "szerda", "csütörtök", "péntek", "szombat", "vasárnap"]

    private static func describe(_ alert: AlertWatch) -> (icon: String, title: String, sub: String) {
        if alert.kind == "traffic" {
            let routes = alert.routeShorts ?? []
            return ("exclamationmark.triangle", "Dugóriasztás \(alert.stopName)", routes.isEmpty ? "bármelyik ide tartó busz" : "csak: \(routes.joined(separator: ", "))")
        }
        if alert.kind == "transfer" {
            let from = alert.params?["fromRoute"]?.string ?? "?"
            let to = alert.params?["toRoute"]?.string ?? "?"
            return ("shuffle", "Átszállás \(alert.stopName)", "\(from) → \(to), szólok, ha veszélybe kerül")
        }
        let walk = alert.params?["walkS"]?.number ?? 0
        let days: String
        switch alert.params?["days"] {
        case .numbers(let list): days = list.map { Self.dayNames[safe: Int($0)] ?? "" }.joined(separator: ", ")
        case .string("workday"): days = "munkanaponként"
        case .string("weekend"): days = "hétvégén"
        default: days = "naponta"
        }
        let when = alert.schedMin.map { "\(days) \(String(format: "%02d:%02d", $0 / 60, $0 % 60))" } ?? "egy menetre"
        let routes = (alert.routeShorts ?? []).isEmpty ? "" : " · \((alert.routeShorts ?? []).joined(separator: ", "))"
        let walkText = walk > 0 ? " · \(Int((walk / 60).rounded())) perc séta" : ""
        return (alert.schedMin != nil ? "repeat" : "figure.walk", "Indulj most \(alert.stopName)", "\(when)\(routes)\(walkText)")
    }

    var body: some View {
        if !alerts.alerts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel("Indulás, dugó, átszállás (\(alerts.alerts.count))")
                VStack(spacing: 0) {
                    ForEach(Array(alerts.alerts.enumerated()), id: \.element.id) { index, alert in
                        let d = Self.describe(alert)
                        if index > 0 { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
                        HStack(spacing: 10) {
                            Image(systemName: d.icon).font(.system(size: 12)).foregroundStyle(Theme.primary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.title).font(Theme.sans(12, weight: .semibold)).lineLimit(1)
                                Text(d.sub + (alert.pushRegistered ? "" : " · push nélkül"))
                                    .font(Theme.sans(11))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                Task { await alerts.remove(stopId: alert.stopId, slot: alert.slot) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.mutedForeground)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(d.title) kikapcsolása")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
        }
    }
}

/// The device's latest pushes: what went out, what did not, and why.
struct DeliveryLog: View {
    let rows: [PushService.Delivery]

    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func meta(_ status: String) -> (label: String, icon: String, tone: Color) {
        switch status {
        case "sent": return ("kiküldve", "checkmark.circle", Theme.ontime)
        case "failed": return ("nem sikerült", "xmark.circle", Theme.destructive)
        case "gone": return ("a feliratkozás lejárt", "xmark.circle", Theme.destructive)
        case "skipped": return ("kihagyva (elkésett volna)", "minus.circle", Theme.mutedForeground)
        default: return ("küldés alatt", "clock", Theme.mutedForeground)
        }
    }

    private static func when(_ iso: String) -> String {
        let date = isoParser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.timeZone = TimeZone(identifier: "Europe/Budapest")
        formatter.dateFormat = "MM. dd. HH:mm"
        return formatter.string(from: date)
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel("Legutóbbi értesítések erre az eszközre")
                ForEach(rows.prefix(12)) { row in
                    let m = Self.meta(row.status)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: m.icon).font(.system(size: 12)).foregroundStyle(m.tone).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title ?? row.stop_name).font(Theme.sans(12, weight: .medium)).lineLimit(1)
                            if let body = row.body {
                                Text(body).font(Theme.sans(11)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                            }
                            Text("\(Self.when(row.created_at)) · \(m.label)\(row.attempts > 1 ? " · \(row.attempts). próbálkozásra" : "")\(row.status == "failed" ? row.last_error.map { " · \($0)" } ?? "" : "")")
                                .font(Theme.mono(10, weight: .regular))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
