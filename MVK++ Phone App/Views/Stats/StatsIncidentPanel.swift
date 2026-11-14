//
//  StatsIncidentPanel.swift
//  MVK++ Phone App
//

import SwiftUI

/// Üzemzavarok (web `IncidentPanel.tsx`): two sharply separated sources —
/// MVK's own cancellation list (certain) and detected stops (a vehicle that
/// went silent mid-trip for 30+ minutes away from known dead zones).
struct StatsIncidentPanel: View {
    let routes: [Route]

    @EnvironmentObject private var navigation: AppNavigation

    @StateObject private var query = StatsQuery<StatsIncidentsV3>()
    @State private var range = "14"
    @State private var kind = "all"

    private static let ranges: [StatsPillItem<String>] = [
        .init(id: "7", label: "7 nap"),
        .init(id: "14", label: "14 nap"),
        .init(id: "30", label: "30 nap"),
    ]

    private static let kinds: [StatsPillItem<String>] = [
        .init(id: "all", label: "Mind"),
        .init(id: "cancelled", label: "MVK-törlés"),
        .init(id: "breakdown", label: "Megállt menet"),
        .init(id: "missed", label: "Kimaradt"),
    ]

    var body: some View {
        let to = StatsFormat.serviceToday()
        let from = StatsFormat.shiftDate(to, -((Int(range) ?? 14) - 1))
        let key = "\(from)|\(to)|\(kind)"

        VStack(alignment: .leading, spacing: 16) {
            StatsLiveIncidentsCard(routes: routes) {
                navigation.isDisruptionsOpen = true
                navigation.tab = .timetable
            }

            VStack(alignment: .leading, spacing: 8) {
                StatsHeading("Üzemzavarok")
                let official = Text("Hivatalos").fontWeight(.semibold).foregroundStyle(Theme.foreground)
                let detected = Text("Észlelt").fontWeight(.semibold).foregroundStyle(Theme.foreground)
                Text("\(official): az MVK által törölt menetek. \(detected): a jármű menet közben elnémult, legalább 30 percig nem jelentkezett, és a hely nem ismert térerő-hiányos szakasz. Csak lezárt napra számoljuk, a mai nap csak a hivatalos törléseket mutatja.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                StatsPillPicker(items: Self.ranges, value: range, onChange: { range = $0 }, groupLabel: "Időszak")
                StatsPillPicker(items: Self.kinds, value: kind, onChange: { kind = $0 }, groupLabel: "Típus")
            }

            StatsQueryBoundary(query, empty: { $0.incidents.isEmpty }) { d in
                StatsIncidentBody(data: d, from: from, to: to)
            }
        }
        .task(id: query.taskId(key)) {
            let k = kind == "all" ? nil : kind
            await query.run(key: key) { try await APIClient.shared.statsIncidentsV3(from: from, to: to, kind: k, minConfidence: 50) }
        }
    }
}

/// Most élőben: trips likely being missed right now (what the header's red
/// badge counts) and today's official MVK cancellations.
struct StatsLiveIncidentsCard: View {
    let routes: [Route]
    let onOpenDisruptions: () -> Void

    @State private var live: StatsLiveIncidents?
    @Environment(\.isTabActive) private var isTabActive

    var body: some View {
        VStack(spacing: 0) {
            if let live {
                card(live)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task(id: isTabActive) {
            guard isTabActive else { return }
            while !Task.isCancelled {
                if let fresh = try? await APIClient.shared.liveIncidents() { live = fresh }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func card(_ live: StatsLiveIncidents) -> some View {
        let byShort = Dictionary(routes.map { ($0.short, $0) }, uniquingKeysWith: { first, _ in first })
        let hasMissing = !live.missing.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if hasMissing {
                        StatsPulseDot(color: Theme.late)
                    } else {
                        Circle().fill(Theme.ontime).frame(width: 8, height: 8)
                    }
                    Text("Most élőben")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                }
                Text(hasMissing
                     ? "Ezek a menetek 15–90 perce esedékesek, egyetlen busz sem kezdte el őket, és késő busz sem tart feléjük, pedig a vonal szomszédos meneteit látjuk. Nem számoljuk az „igény esetén” járatokat, a garázsból kiálló meneteket (alattuk a fedélzeti egység gyakran még nem küld adatot), és azt sem, amelyiket a busz láthatóan levitt, csak adat nélkül."
                     : "Most nincs valószínűleg kimaradó menet.")
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 8, lineSpacing: 8) {
                    let count = Text("\(live.cancelled)").fontWeight(.semibold).foregroundStyle(Theme.foreground)
                    Text("Ma \(count) hivatalos MVK-törlés")
                        .font(Theme.sans(11.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    Button(action: onOpenDisruptions) {
                        HStack(spacing: 6) {
                            Text("Mi marad ki, mi jön helyette")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(Theme.sans(11.5, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).strokeBorder(Theme.primary.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if hasMissing {
                VStack(spacing: 0) {
                    ForEach(Array(live.missing.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Divider().overlay(Theme.border.opacity(0.6)) }
                        let r = byShort[m.route]
                        HStack(spacing: 12) {
                            RouteTile(short: m.route, colorHex: r?.color, textHex: r?.text)
                            Text(m.time)
                                .font(Theme.mono(14, weight: .semibold))
                                .foregroundStyle(Theme.foreground)
                            Text(m.headsign)
                                .font(Theme.sans(13))
                                .foregroundStyle(Theme.foreground)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(m.lateMin) perce esedékes")
                                .font(Theme.sans(12, weight: .semibold))
                                .foregroundStyle(Theme.late)
                                .fixedSize()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(16)
        .statsCard(fill: hasMissing ? Theme.late.opacity(0.06) : Theme.card, stroke: hasMissing ? Theme.late.opacity(0.4) : Theme.border)
    }
}

private struct StatsIncidentBody: View {
    let data: StatsIncidentsV3
    let from: String
    let to: String

    private struct KindMeta {
        let label: String
        let icon: String
        let tone: Color
    }

    private static func meta(_ kind: String) -> KindMeta {
        switch kind {
        case "cancelled": return KindMeta(label: "Az MVK törölte", icon: "nosign", tone: Theme.destructive)
        case "missed": return KindMeta(label: "Valószínűleg kimaradt", icon: "exclamationmark.circle", tone: Theme.late)
        case "breakdown": return KindMeta(label: "Menet közben megállt", icon: "dot.radiowaves.left.and.right", tone: Theme.late)
        case "detour": return KindMeta(label: "Terelés", icon: "exclamationmark.circle", tone: Theme.mutedForeground)
        default: return KindMeta(label: "Hosszú állás", icon: "exclamationmark.circle", tone: Theme.mutedForeground)
        }
    }

    var body: some View {
        let cancelled = data.incidents.filter { $0.kind == "cancelled" }.count
        let detected = data.incidents.filter { $0.source == "detected" }.count
        var byRoute: [String: Int] = [:]
        var routeOrder: [String] = []
        for i in data.incidents {
            guard let r = i.route_short else { continue }
            if byRoute[r] == nil { routeOrder.append(r) }
            byRoute[r, default: 0] += 1
        }
        // A tie goes to the route met first, as the web's stable sort does.
        let top = routeOrder.reduce(nil as (key: String, value: Int)?) { best, r in
            let n = byRoute[r] ?? 0
            return n > (best?.value ?? 0) ? (r, n) : best
        }
        var days: [StatsBarDatum] = []
        var dd = from
        while dd <= to {
            let n = data.byDay.filter { $0.service_date == dd }.reduce(0) { $0 + $1.n }
            days.append(StatsBarDatum(label: String(dd.suffix(2)), value: Double(n), title: "\(dd): \(n) esemény"))
            dd = StatsFormat.shiftDate(dd, 1)
        }

        return VStack(alignment: .leading, spacing: 16) {
            StatsTileGrid {
                StatsStatTile(label: "Törölt menet (MVK)", value: String(cancelled), sub: "hivatalos adat", tone: .late)
                StatsStatTile(label: "Észlelt megállás", value: String(detected), sub: "bizonyítékkal, ≥50% megbízhatóság")
                StatsStatTile(label: "Leginkább érintett vonal", value: top?.key ?? "", sub: top.map { "\($0.value) esemény" })
            }

            StatsChartFrame(title: "Események naponta", hint: "a kiválasztott típusú események száma") {
                StatsBarChart(data: days, labelEvery: Int(ceil(Double(days.count) / 10)))
            }

            StatsChartFrame(title: "Részletek", hint: "\(data.incidents.count) esemény, legújabb elöl") {
                LazyVStack(spacing: 0) {
                    ForEach(Array(data.incidents.prefix(200).enumerated()), id: \.element.id) { i, inc in
                        if i > 0 { Divider().overlay(Theme.border.opacity(0.6)) }
                        row(inc)
                    }
                }
            }
        }
    }

    private func row(_ i: StatsIncidentV3) -> some View {
        let meta = Self.meta(i.kind)
        return HStack(alignment: .top, spacing: 12) {
            if let route = i.route_short {
                RouteTile(short: route, colorHex: i.color ?? "888888", textHex: i.text_color ?? "FFFFFF")
            } else {
                Color.clear.frame(width: 36, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: meta.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(meta.tone)
                    Text(i.title)
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                }
                if let detail = i.detail {
                    Text(detail)
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Text(i.service_date)
                    Text(StatsFormat.clock(i.started_ts))
                    if let vehicle = i.vehicle_id {
                        Text(vehicle)
                            .font(Theme.mono(10, weight: .bold))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 4)
                            .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    if i.source == "mvk" {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.seal")
                            Text("MVK")
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.foreground)
                    } else {
                        Text("\(i.confidence)% biztos")
                    }
                }
                .font(Theme.sans(10))
                .monospacedDigit()
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
}
