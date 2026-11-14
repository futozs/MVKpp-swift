//
//  RelationCard.swift
//  MVK++ Phone App
//

import SwiftUI

/// A to B directly (e.g. Miskolc-Tiszai → Füzesabony) — the web app's
/// `RelationCard`. Only runs stopping at both: departure from A with platform
/// and delay, arrival at B, travel time, and MÁV's notices.
struct RelationCard: View {
    let relation: RelationWatch
    let stops: [Stop]
    var onRemove: () -> Void
    var onFocusTrip: ((String, String?) -> Void)?

    @State private var data: RelationBoardResponse?
    @State private var error: FriendlyError?

    private static let rowCount = 8

    var body: some View {
        BoardCard {
            header
            HairlineDivider()
            hero
            HairlineDivider()
            list
        }
        .visiblePoll(id: relation.id, every: .seconds(20)) { await load() }
    }

    private func name(_ id: String, fallback: String?) -> String {
        stops.first { $0.id == id }?.name ?? fallback ?? id
    }

    private var fromName: String { name(relation.from, fallback: data?.from.name) }
    private var toName: String { name(relation.to, fallback: data?.to.name) }

    private func load() async {
        do {
            data = try await APIClient.shared.relation(from: relation.from, to: relation.to, limit: Self.rowCount)
            error = nil
        } catch {
            guard !(error is CancellationError) else { return }
            self.error = FriendlyError(error)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(fromName).lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                    Text(toName).lineLimit(1)
                }
                .font(Theme.sans(16, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Theme.foreground)

                HStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 10))
                    Text("Viszonylat · közvetlen járatok")
                }
                .font(Theme.sans(11))
                .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GhostIconButton(systemName: "trash", label: "\(fromName) → \(toName) levétele a figyelőről", destructive: true, action: onRemove)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error {
                RetryNotice(error: error, title: "Hiba, újrapróbálom…").padding(.bottom, 10)
            }
            if data == nil {
                if error == nil { BoardPlaceholder(text: "Járatok lekérése…", mono: true) }
            } else if let next = data?.rows.first {
                heroRow(next)
            } else {
                BoardPlaceholder(text: "Ma és holnap nincs több közvetlen járat a kettő között.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted.opacity(0.3))
    }

    private func heroRow(_ next: RelationRow) -> some View {
        let now = RealtimeClient.shared.serverNow
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                BoardEyebrow(text: "Következő")
                Spacer()
                if next.cancelled { CancelledTag(prominent: true) } else { LiveTag(live: next.live) }
            }
            .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 12) {
                RouteTile(short: Self.tileText(next), colorHex: next.color, textHex: next.text, size: .large)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.title(next))
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("\(next.depTime) → \(next.arrTime)")
                            .font(Theme.mono(12, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                            .strikethrough(next.cancelled, color: Theme.destructive.opacity(0.7))
                        PlatformBadge(platform: next.platform, predicted: next.platformPredicted == true, mode: next.mode)
                        if !next.cancelled { DelayBar(delaySec: next.depDelaySec) }
                    }
                    Text("\(next.durationMin) perc · \(next.stops - 2 > 0 ? "\(next.stops - 2) megálló közben" : "megállás nélkül")")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if next.cancelled {
                    Text("nem jön")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.destructive)
                        .padding(.top, 4)
                } else {
                    CountdownView(etaMin: max(0, Int(((next.depUnix - now) / 60).rounded())))
                }
            }

            NoticeList(notices: next.notices).padding(.top, 10)
        }
    }

    private var list: some View {
        let rows = Array((data?.rows ?? []).dropFirst())
        let now = RealtimeClient.shared.serverNow
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { HairlineDivider(opacity: 0.6) }
                    rowView(row, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: RelationRow, now: Double) -> some View {
        let focusable = onFocusTrip != nil && row.live && !row.cancelled
        let content = HStack(spacing: 12) {
            RouteTile(short: Self.tileText(row), colorHex: row.color, textHex: row.text)
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title(row))
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    PlatformBadge(platform: row.platform, predicted: row.platformPredicted == true, mode: row.mode, compact: true)
                    if row.cancelled { CancelledTag() }
                    Text("\(row.depTime) → \(row.arrTime)")
                        .font(Theme.mono(11, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                        .strikethrough(row.cancelled, color: Theme.destructive.opacity(0.7))
                    if !row.cancelled { DelayBar(delaySec: row.depDelaySec, showLabel: false) }
                    if !row.today {
                        Text("holnap")
                            .font(Theme.sans(10, weight: .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                NoticeList(notices: row.notices, compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RowEta(minutes: max(0, Int(((row.depUnix - now) / 60).rounded())), cancelled: row.cancelled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())

        if focusable, let onFocusTrip {
            Button { onFocusTrip(row.tripId, row.vehicle?.id) } label: { content }
                .buttonStyle(RowHighlightStyle())
        } else {
            content
        }
    }

    static func tileText(_ row: RelationRow) -> String {
        if row.mode == .rail, let trainNo = row.trainNo { return "\(row.route) \(trainNo)" }
        return row.route
    }

    static func title(_ row: RelationRow) -> String {
        row.trainName.map { "\($0) → \(row.headsign)" } ?? row.headsign
    }
}
