//
//  StatsNetworkRegionalPanels.swift
//  MVK++ Phone App
//

import SwiftUI

// MARK: - Hálózat

/// Hálózat (web `NetworkPanel.tsx`): when and where the network runs late,
/// from every stop event, averaged by day type.
struct StatsNetworkPanel: View {
    private struct DayType {
        let id: String
        let label: String
        /// Separate inflected forms: "vasárnap, ünnep" + "-jai" is not Hungarian.
        let of: String
        let on: String
    }

    private static let daytypes = [
        DayType(id: "0", label: "Munkanap", of: "munkanapjai", on: "munkanapjain"),
        DayType(id: "1", label: "Szombat", of: "szombatjai", on: "szombatjain"),
        DayType(id: "2", label: "Vasárnap, ünnep", of: "vasár- és ünnepnapjai", on: "vasár- és ünnepnapjain"),
    ]

    private static let periods: [StatsPillItem<String>] = [
        .init(id: "30", label: "30 nap"),
        .init(id: "60", label: "60 nap"),
        .init(id: "120", label: "120 nap"),
    ]

    private struct Window {
        let id: String
        let label: String
        let sub: String
        let from: Int
        let to: Int
    }

    private static let windows = [
        Window(id: "am", label: "Reggeli csúcs", sub: "6–9", from: 6, to: 9),
        Window(id: "mid", label: "Napközben", sub: "9–14", from: 9, to: 14),
        Window(id: "pm", label: "Délutáni csúcs", sub: "14–18", from: 14, to: 18),
        Window(id: "eve", label: "Este", sub: "18–23", from: 18, to: 23),
    ]

    @StateObject private var query = StatsQuery<StatsNetworkProfile>()
    @State private var daytype = "0"
    @State private var period = "30"
    @State private var win = "am"

    var body: some View {
        let w = Self.windows.first { $0.id == win } ?? Self.windows[0]
        let key = "\(daytype)|\(period)|\(w.from)|\(w.to)"
        let dayType = Self.daytypes.first { $0.id == daytype } ?? Self.daytypes[0]

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                StatsHeading("Hálózat")
                StatsPillPicker(items: Self.daytypes.map { StatsPillItem(id: $0.id, label: $0.label) }, value: daytype, onChange: { daytype = $0 }, groupLabel: "Naptípus")
                StatsPillPicker(items: Self.periods, value: period, onChange: { period = $0 }, groupLabel: "Időszak")
            }

            StatsQueryBoundary(query, empty: { $0.hourly.isEmpty }) { d in
                content(d, window: w, dayType: dayType)
            }
        }
        .task(id: query.taskId(key)) {
            let dt = Int(daytype) ?? 0
            let days = Int(period) ?? 30
            await query.run(key: key) { try await APIClient.shared.statsNetwork(daytype: dt, days: days, fromHour: w.from, toHour: w.to) }
        }
    }

    private func avgOver(_ hours: [StatsNetworkHour], from: Int, to: Int) -> (delay: Double, otp: Int)? {
        let sel = hours.filter { $0.hour >= from && $0.hour < to && $0.avg_delay_s != nil }
        let n = sel.reduce(0) { $0 + $1.n }
        guard n > 0 else { return nil }
        return (
            (sel.reduce(0.0) { $0 + ($1.avg_delay_s ?? 0) * Double($1.n) } / Double(n)).rounded(),
            Int((sel.reduce(0.0) { $0 + ($1.otp_pct ?? 0) * Double($1.n) } / Double(n)).rounded())
        )
    }

    private func content(_ d: StatsNetworkProfile, window w: Window, dayType: DayType) -> some View {
        let am = avgOver(d.hourly, from: 6, to: 9)
        let pm = avgOver(d.hourly, from: 14, to: 18)
        let worst = d.hourly.filter { $0.n >= 50 && $0.hour >= 5 && $0.hour <= 23 }.max { ($0.avg_delay_s ?? 0) < ($1.avg_delay_s ?? 0) }
        let totalN = d.hourly.reduce(0) { $0 + $1.n }

        return VStack(alignment: .leading, spacing: 16) {
            StatsTileGrid {
                StatsStatTile(label: "Reggeli csúcs (6–9)", value: StatsFormat.minutes(am?.delay), sub: am.map { "\($0.otp)% pontos érkezés" } ?? "nincs adat", tone: .late)
                StatsStatTile(label: "Délutáni csúcs (14–18)", value: StatsFormat.minutes(pm?.delay), sub: pm.map { "\($0.otp)% pontos érkezés" } ?? "nincs adat", tone: .late)
                StatsStatTile(label: "Legrosszabb óra", value: worst.map { "\($0.hour % 24):00–\($0.hour % 24 + 1):00" } ?? "", sub: worst.map { "átlag \(StatsFormat.minutes($0.avg_delay_s))" })
                StatsStatTile(label: "Mérések", value: StatsFormat.number(totalN), sub: "megálló-érkezés, \(d.days) nap \(dayType.of)")
            }

            StatsChartFrame(
                title: "Átlagos késés a nap folyamán",
                hint: "Megállónkénti érkezés a menetrendhez képest, az elmúlt \(d.days) nap \(dayType.on). Pontos = 1 perc sietés és 5 perc késés között."
            ) {
                StatsBarChart(
                    data: d.hourly.filter { $0.hour >= 4 && $0.hour <= 24 }.map { h in
                        let v = h.avg_delay_s ?? 0
                        return StatsBarDatum(
                            label: String(h.hour % 24),
                            value: h.avg_delay_s.map { ($0 / 6).rounded() / 10 },
                            tone: v > 180 ? Theme.late : v < -30 ? Theme.early : Theme.ontime,
                            title: "\(h.hour % 24):00–\(h.hour % 24 + 1):00 · átlag \(StatsFormat.minutes(h.avg_delay_s)) · \(h.otp_pct.map { StatsFormat.raw($0) } ?? "")% pontos · 85%-ban legfeljebb \(StatsFormat.minutes(h.p85_delay_s)) · \(h.n) mérés"
                        )
                    },
                    unit: "p",
                    labelEvery: 2
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                StatsPillPicker(items: Self.windows.map { StatsPillItem(id: $0.id, label: $0.label, sub: $0.sub) }, value: win, onChange: { win = $0 }, groupLabel: "Napszak")
                StatsChartFrame(
                    title: "Hol lassul be a forgalom",
                    hint: "\(w.label) (\(w.sub) óra) · megállóközök, ahol a buszok a menetrendnél a legtöbbet lassabbak (medián menetidő − menetrendi idő)"
                ) {
                    if d.slow.isEmpty {
                        Text("Ebben a napszakban még kevés a mérés.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        StatsRankBars(rows: d.slow.prefix(15).map { s in
                            StatsRankRow(
                                label: "\(s.from_name) → \(s.to_name)",
                                sub: "terv \(tenth(s.sched_s)) p · tény \(tenth(s.p50_s)) p (85%: \(tenth(s.p85_s)) p) · \(s.n) áthaladás",
                                value: max(0, s.excess_s),
                                display: "+\(tenth(s.excess_s)) p\(s.excess_pct.map { " (\(StatsFormat.raw($0))%)" } ?? "")"
                            )
                        })
                    }
                }
            }
        }
    }

    /// `Math.round(s / 6) / 10` — minutes with one decimal, trailing zero dropped.
    private func tenth(_ sec: Double) -> String {
        StatsFormat.plain((sec / 6).rounded() / 10).replacingOccurrences(of: ",", with: ".")
    }
}

// MARK: - Vasút és Volán

/// Vasút és Volán (web `RegionalPanel.tsx`): punctuality measured from the
/// MÁV+ data in the county — per stop, per train at its terminus, the delay
/// causes MÁV publishes, and platform changes.
struct StatsRegionalPanel: View {
    let modes: [TransitMode]

    private enum Scope: String { case all, rail, coach }

    private static let periods: [StatsPillItem<String>] = [
        .init(id: "7", label: "7 nap"),
        .init(id: "30", label: "30 nap"),
        .init(id: "90", label: "90 nap"),
    ]

    private static let kindLabel = ["composition": "kocsiösszeállítás", "replacement": "pótlás", "other": "közlemény"]

    @StateObject private var query = StatsQuery<StatsRegional>()
    @State private var scope: Scope?
    @State private var period = "30"

    private var both: Bool { modes.contains(.coach) && modes.contains(.rail) }

    private var active: Scope {
        if both { return scope ?? .all }
        return modes.contains(.rail) ? .rail : .coach
    }

    private func scopeModes(_ s: Scope) -> String {
        switch s {
        case .all: return "coach,rail"
        case .rail: return "rail"
        case .coach: return "coach"
        }
    }

    var body: some View {
        let modesQuery = scopeModes(active)
        let key = "\(period)|\(modesQuery)"
        let nouns = active == .coach ? "járatok" : active == .rail ? "vonatok" : "vonatok és járatok"

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                StatsHeading("Vasút és Volán")
                if both {
                    StatsPillPicker(
                        items: [StatsPillItem(id: Scope.all, label: "Mind"), .init(id: .rail, label: "Vonat"), .init(id: .coach, label: "Volán")],
                        value: active,
                        onChange: { scope = $0 },
                        groupLabel: "Mód"
                    )
                }
                StatsPillPicker(items: Self.periods, value: period, onChange: { period = $0 }, groupLabel: "Időszak")
            }

            StatsQueryBoundary(query, empty: { !($0.summary?.n ?? 0 > 0) && $0.trains.isEmpty && $0.causes.isEmpty }) { d in
                content(d, nouns: nouns)
            }
        }
        .task(id: query.taskId(key)) {
            let days = Int(period) ?? 30
            await query.run(key: key) { try await APIClient.shared.statsRegional(days: days, modes: modesQuery) }
        }
    }

    /// A train by category and number ("Sz 6612"), a Volán run by route/run ("4001/748").
    private func trainLabel(_ t: StatsRegional.Train) -> String {
        t.kind == "RAIL" && t.short_name != nil ? "\(t.short_name ?? "") \(t.name)" : t.name
    }

    private func content(_ d: StatsRegional, nouns: String) -> some View {
        let s = d.summary
        let causes = d.causes.filter { $0.kind == "cause" }
        let other = d.causes.filter { $0.kind != "cause" }
        let worst = Array(d.trains.filter { $0.avg_end_delay_s != nil }.prefix(15))
        let changed = d.platforms?.changed ?? 0
        let platformsN = d.platforms?.n ?? 0

        return VStack(alignment: .leading, spacing: 16) {
            StatsTileGrid {
                StatsStatTile(label: "Pontos érkezés", value: s?.ontime.map { "\(StatsFormat.raw($0))%" } ?? "", sub: (s?.n ?? 0) > 0 ? "\(StatsFormat.number(s?.n ?? 0)) megálló-érkezés" : "nincs adat", tone: .ontime)
                StatsStatTile(label: "Átlagos késés", value: StatsFormat.minutes(s?.avg_delay_s), sub: s?.late.map { "\(StatsFormat.raw($0))% több mint 5 perccel késett" }, tone: .late)
                StatsStatTile(label: "85%-ban legfeljebb", value: StatsFormat.minutes(s?.p85_delay_s), sub: "a megállókban mért késés")
                StatsStatTile(
                    label: "Vágány / kocsiállás",
                    value: platformsN > 0 ? "\(changed) változás" : "",
                    sub: platformsN > 0 ? "\(StatsFormat.number(platformsN)) figyelt indulásból" : "a figyelt állomásokon",
                    tone: changed > 0 ? .late : .standard
                )
            }

            if d.daily.count > 1 {
                StatsChartFrame(title: "Átlagos késés naponta", hint: "Megállónkénti érkezés a menetrendhez képest, az elmúlt \(d.days) nap. Pontos = 1 perc sietés és 5 perc késés között.") {
                    StatsBarChart(
                        data: d.daily.map { x in
                            let v = x.avg_delay_s ?? 0
                            return StatsBarDatum(
                                label: String(x.date.dropFirst(5)).replacingOccurrences(of: "-", with: "."),
                                value: x.avg_delay_s.map { ($0 / 6).rounded() / 10 },
                                tone: v > 180 ? Theme.late : v < -30 ? Theme.early : Theme.ontime,
                                title: "\(x.date) · átlag \(StatsFormat.minutes(x.avg_delay_s)) · \(x.ontime.map { StatsFormat.raw($0) } ?? "")% pontos · \(x.n) mérés"
                            )
                        },
                        unit: "p"
                    )
                }
            }

            StatsChartFrame(title: "Legtöbbet késő \(nouns)", hint: "A végállomáson (vagy a megye határán túli utolsó jelnél) mért átlagos késés; legalább két lefutott menet.") {
                if worst.isEmpty {
                    Text("Ehhez még kevés a lefutott menet pár nap múlva telik meg.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    StatsRankBars(rows: worst.map { t in
                        StatsRankRow(
                            sub: "\(t.runs) menet · \(t.ontime_pct.map { StatsFormat.raw($0) } ?? "")% pontos · 85%-ban legfeljebb \(StatsFormat.minutes(t.p85_end_delay_s))",
                            value: max(0, t.avg_end_delay_s ?? 0),
                            display: StatsFormat.minutes(t.avg_end_delay_s)
                        ) {
                            RouteTile(short: trainLabel(t), colorHex: t.color ?? "1E5AA8", textHex: t.text_color ?? "FFFFFF", size: .small)
                        }
                    })
                }
            }

            StatsChartFrame(title: "A késések okai", hint: "A MÁV hivatalos megjegyzései a menetekhez: hány menetnél szerepelt az ok.") {
                VStack(alignment: .leading, spacing: 0) {
                    if causes.isEmpty {
                        Text("Ebben az időszakban nem volt közölt késésok.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        StatsRankBars(rows: causes.prefix(12).map { StatsRankRow(label: $0.text, value: Double($0.n), display: "\($0.n) menet") })
                    }
                    if !other.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider().overlay(Theme.border)
                            Text("EGYÉB KÖZLEMÉNYEK")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(Theme.mutedForeground)
                            StatsRankBars(rows: other.prefix(6).map { c in
                                StatsRankRow(label: c.text, sub: Self.kindLabel[c.kind] ?? c.kind, value: Double(c.n), display: "\(c.n) menet", bar: Theme.primary.opacity(0.6))
                            })
                        }
                        .padding(.top, 20)
                    }
                }
            }
        }
    }
}
