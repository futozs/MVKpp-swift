//
//  StatsOverviewPanel.swift
//  MVK++ Phone App
//

import SwiftUI

/// Áttekintés (web `OverviewPanel.tsx`): the delay model, plate prediction
/// accuracy and the warehouse's own health.
struct StatsOverviewPanel: View {
    let onJumpToVehicles: () -> Void

    @StateObject private var query = StatsQuery<StatsHealth>()

    private static let jobLabels: [String: String] = [
        "janitor": "Partíciógondozás",
        "profile": "Szakaszprofil",
        "ghosts": "Szellemmenetek",
        "roll:route": "Vonal-összegzés",
        "roll:stop": "Megálló-összegzés",
        "roll:vehicle": "Jármű-összegzés",
        "roll:vehroute": "Jármű–vonal megoszlás",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            StatsForecastModelCard()
            StatsPredictionOverview()
            StatsQueryBoundary(query) { d in
                health(d)
            }
        }
        .task(id: query.taskId("health")) {
            await query.run(key: "health") { try await APIClient.shared.statsHealth() }
        }
    }

    private func health(_ d: StatsHealth) -> some View {
        let t = d.today
        let dedup: String? = t.flatMap { $0.pings_kept > 0 ? StatsFormat.oneDecimal(Double($0.pings_dup) / Double($0.pings_kept) + 1) : nil }
        let pollTotal = t.map { $0.polls_ok + $0.polls_fail } ?? 0
        let uptime: Int? = pollTotal > 0 ? Int((Double(t?.polls_ok ?? 0) / Double(pollTotal) * 100).rounded()) : nil

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                StatsHeading("Adatraktár")
                Spacer()
                Button(action: query.reload) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, isActive: query.loading)
                        Text("Frissítés")
                    }
                }
                .buttonStyle(StatsButtonStyle())
                .disabled(query.loading)
            }

            StatsTileGrid {
                StatsStatTile(label: "Megálló-esemény", value: StatsFormat.number(d.counts.events), sub: "a tények aranykészlete")
                StatsStatTile(label: "Szakaszmérés", value: StatsFormat.number(d.counts.segments), sub: "ebből lesz az A→B becslés")
                StatsStatTile(label: "Menet", value: StatsFormat.number(d.counts.runs), sub: "teljesített és megkezdett")
                StatsStatTile(label: "Nyers GPS-pont", value: StatsFormat.number(d.counts.pings), sub: "14 napig őrizve")
                StatsStatTile(label: "Szakaszprofil", value: StatsFormat.number(d.counts.profiles), sub: "napszakonként")
                StatsStatTile(label: "Ismert jármű", value: StatsFormat.number(d.counts.vehicles))
            }

            if let t {
                StatsChartFrame(title: "Mai gyűjtés", hint: "Üzemi nap: \(t.service_date)") {
                    Button(action: onJumpToVehicles) {
                        HStack(spacing: 8) {
                            Text("Járművek")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(StatsButtonStyle(variant: .ghost))
                } content: {
                    StatsTileGrid {
                        StatsStatTile(
                            label: "Feed elérhetőség",
                            value: uptime.map { "\($0)%" } ?? "",
                            sub: "\(StatsFormat.number(t.polls_ok)) sikeres, \(StatsFormat.number(t.polls_fail)) hibás",
                            tone: (uptime ?? 100) < 95 ? .late : .ontime
                        )
                        StatsStatTile(label: "Megtartott pont", value: StatsFormat.number(t.pings_kept), sub: dedup.map { "\($0)× ismétlés kiszűrve" })
                        StatsStatTile(label: "Csúcs járműszám", value: String(t.vehicles_max), sub: "egyidejűleg")
                        StatsStatTile(label: "Eldobott ismétlés", value: StatsFormat.number(t.pings_dup), sub: "kulcsütközésre, ingyen")
                    }
                }
            }

            StatsChartFrame(title: "Feldolgozási feladatok") {
                if d.jobs.isEmpty {
                    Text("Még nem futott feldolgozási feladat.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(d.jobs.enumerated()), id: \.offset) { i, j in
                            if i > 0 { Divider().overlay(Theme.border) }
                            HStack(spacing: 10) {
                                Image(systemName: j.ok != 0 ? "checkmark.circle" : "xmark.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(j.ok != 0 ? Theme.ontime : Theme.late)
                                Text(Self.jobLabels[j.job] ?? j.job)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if j.rows_out != 0 {
                                    Text("\(StatsFormat.number(j.rows_out)) sor")
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.mutedForeground)
                                }
                                Text(jobTime(j.started_at))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                            .font(.system(size: 12))
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private func jobTime(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let text = raw.replacingOccurrences(of: " ", with: "T")
        guard let date = iso.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? Self.localTime(text) else { return "" }
        let f = DateFormatter()
        f.locale = StatsFormat.hu
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// A timestamp without an offset (`2026-11-14 03:00:00`) is local time,
    /// as `new Date()` reads it on the web.
    private static func localTime(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(text.prefix(19)))
    }
}

/// Késés-előrejelzés (web `ForecastModelCard.tsx`): what estimates now, and
/// the last training measured on never-seen test days.
struct StatsForecastModelCard: View {
    @StateObject private var query = StatsQuery<StatsForecastStatus>()

    private static let order = ["1-3", "4-6", "7-10", "11-15", "16+"]
    private static let horizonLabel = ["1-3": "1–3", "4-6": "4–6", "7-10": "7–10", "11-15": "11–15", "16+": "16+"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.primary)
                    StatsHeading("Késés-előrejelzés")
                }
                Text("Tanított modell (kvantilis gradient boosting): a mostani forgalmat, az előtte járó buszt, a busz késés-trendjét és az időjárást is nézi. Éjszakánként újratanul, és csak ott becsül, ahol a tanításból kihagyott napokon bizonyítottan pontosabb a régi képletnél.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StatsQueryBoundary(query) { d in
                report(d)
            }
        }
        .task(id: query.taskId("ml")) {
            await query.run(key: "ml") { try await APIClient.shared.forecastModelStatus() }
        }
    }

    @ViewBuilder
    private func report(_ d: StatsForecastStatus) -> some View {
        if let rep = d.inUse.report ?? d.lastTraining?.report {
            let active = d.inUse.trainedAt != nil
            let weak = (rep.cells ?? [:]).filter { !$0.value.useMedian }.map(\.key).sorted()
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(active ? Theme.ontime : Theme.mutedForeground).frame(width: 6, height: 6)
                        Text(active ? "Modell becsül" : "Képlet becsül")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(active ? Theme.ontime : Theme.mutedForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(active ? Theme.ontime.opacity(0.15) : Theme.muted, in: RoundedRectangle(cornerRadius: 10))

                    let before = Text("\(fmt(rep.overall.maeBaseline)) mp").font(Theme.mono(14, weight: .bold))
                    let after = Text("\(fmt(rep.overall.maeModel)) mp").font(Theme.mono(14, weight: .bold)).foregroundStyle(Theme.ontime)
                    let gain = Text("(\(fmt(rep.overall.improvement))% pontosabb)").foregroundStyle(Theme.mutedForeground)
                    Text("átlagos hiba \(before) → \(after) \(gain)")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.foreground)

                    Text("tanítva \(d.inUse.trainedAt.map(trainedLabel) ?? "") · \(rep.days.train.count) nap, \(StatsFormat.number(rep.rows.train)) minta · teszt: \(rep.days.test.count) sosem látott nap")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                        GridRow {
                            header("Megálló előre")
                            header("Képlet hibája")
                            header("Modell hibája")
                            header("„Legkésőbb” tart")
                            header("Becslő")
                        }
                        .padding(.vertical, 6)
                        Divider().overlay(Theme.border)
                        let rows = rep.buckets.sorted { (Self.order.firstIndex(of: $0.key) ?? 99) < (Self.order.firstIndex(of: $1.key) ?? 99) }
                        ForEach(Array(rows.enumerated()), id: \.element.key) { i, entry in
                            let b = entry.value
                            GridRow {
                                Text(Self.horizonLabel[entry.key] ?? entry.key)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("\(fmt(b.maeBaseline)) mp")
                                Text("\(fmt(b.maeModel)) mp")
                                    .fontWeight(b.maeModel < b.maeBaseline ? .bold : .regular)
                                    .foregroundStyle(b.maeModel < b.maeBaseline ? Theme.ontime : Theme.foreground)
                                let formula = Text("(képlet \(Int((b.coverBaseline * 100).rounded()))%)").foregroundStyle(Theme.mutedForeground)
                                Text("\(Int((b.coverModel * 100).rounded()))% \(formula)")
                                Text(b.useMedian ? "modell" : "képlet")
                                    .font(.system(size: 12.5))
                            }
                            .font(Theme.mono(12.5, weight: .regular))
                            .foregroundStyle(Theme.foreground)
                            .padding(.vertical, 6)
                            if i < rows.count - 1 { Divider().overlay(Theme.border.opacity(0.5)) }
                        }
                    }
                    .frame(minWidth: 480, alignment: .leading)
                }

                if !weak.isEmpty {
                    Text("A képlet marad itt (a modell nem volt legalább 3%-kal jobb): \(weak.map { $0.replacingOccurrences(of: "|", with: " · ") }.joined(separator: ", ")).")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .statsCard()
        } else {
            Text("Még nincs tanított modell a képlet becsül. Az első tanítás a worker indulása után pár perccel, utána minden éjjel fut.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .statsDashed()
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Theme.mutedForeground)
            .fixedSize()
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func trainedLabel(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return "" }
        let f = DateFormatter()
        f.locale = StatsFormat.hu
        f.timeZone = StatsFormat.budapest
        f.dateFormat = "MMM d. HH:mm"
        return f.string(from: date)
    }
}
