//
//  TrainCard.swift
//  MVK++ Phone App
//

import SwiftUI

/// A train by number, every day (e.g. 5139) — the web app's `TrainCard`:
/// today's run, or tomorrow's once today's has gone. Where it is, how late
/// and why, and the stops still ahead with their platforms.
struct TrainCard: View {
    let trainNo: String
    var onRemove: () -> Void
    var onFocusTrip: ((String, String?) -> Void)?

    @State private var data: TrainDetailResponse?
    @State private var error: FriendlyError?

    /// How many stops already passed stay in view, to read "where is it".
    private static let passedShown = 1

    var body: some View {
        BoardCard {
            header
            HairlineDivider()
            hero
            if data?.found == true, !shownStops.isEmpty {
                HairlineDivider()
                stopList
            }
        }
        .visiblePoll(id: trainNo, every: .seconds(20)) { await load() }
    }

    private func load() async {
        do {
            data = try await APIClient.shared.train(no: trainNo)
            error = nil
        } catch {
            guard !(error is CancellationError) else { return }
            self.error = FriendlyError(error)
        }
    }

    private var stops: [TrainStop] { data?.stops ?? [] }
    private var firstUpcoming: Int? { stops.firstIndex { !$0.passed } }

    private var shownStops: [TrainStop] {
        guard let firstUpcoming else { return Array(stops.suffix(1)) }
        return Array(stops[max(0, firstUpcoming - Self.passedShown)...])
    }

    private var delay: Int? { data?.officialDelaySec ?? data?.liveDelaySec }
    private var live: Bool { data?.vehicle != nil }

    private var title: String {
        guard let data, data.found else { return "\(HungarianText.withSuffix(trainNo)) vonat" }
        return "\(data.trainName.map { "\($0) → " } ?? "")\(data.headsign ?? "")"
    }

    private var tile: String {
        data?.category.map { "\($0) \(trainNo)" } ?? trainNo
    }

    private var whereText: String? {
        guard data?.cancelled != true, live, let firstUpcoming else { return nil }
        let next = stops[firstUpcoming]
        if firstUpcoming > 0 { return "\(stops[firstUpcoming - 1].name) és \(next.name) között" }
        return "\(next.name) felé"
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                RouteTile(short: tile, colorHex: data?.route?.color ?? "1E5AA8", textHex: data?.route?.text ?? "FFFFFF", size: .large, capsule: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.sans(16, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: "train.side.front.car")
                            .font(.system(size: 10))
                        Text(subtitle)
                    }
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                if let data, data.vehicle != nil, let tripId = data.tripId, let onFocusTrip {
                    GhostIconButton(systemName: "scope", label: "Követés a térképen") {
                        onFocusTrip(tripId, data.vehicle?.id)
                    }
                }
                GhostIconButton(systemName: "trash", label: "A \(HungarianText.withSuffix(trainNo)) vonat levétele a figyelőről", destructive: true, action: onRemove)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        guard let data, data.found else { return "Vonatszám figyelése" }
        return data.today == true ? (data.name ?? trainNo) : "holnap · \(data.name ?? trainNo)"
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error {
                RetryNotice(error: error, title: "Hiba, újrapróbálom…").padding(.bottom, 10)
            }
            if let data {
                if data.found {
                    found(data)
                } else {
                    BoardPlaceholder(text: "Ma és holnap nem közlekedik \(HungarianText.withSuffix(trainNo)) vonat a megyét érintve.")
                }
            } else if error == nil {
                BoardPlaceholder(text: "A vonat lekérése…", mono: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted.opacity(0.3))
    }

    private func found(_ data: TrainDetailResponse) -> some View {
        let firstDep = stops.first
        let eyebrow = live ? "Most" : data.today == true && (firstDep?.depUnix ?? 0) > Date().timeIntervalSince1970 ? "Indul" : "Menetrend"
        let line = data.cancelled == true
            ? "Ma nem közlekedik."
            : whereText ?? firstDep.map { "\($0.name), \($0.schedDep)" } ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                BoardEyebrow(text: eyebrow)
                Spacer()
                if data.cancelled == true { CancelledTag(prominent: true) } else { LiveTag(live: live || delay != nil) }
            }
            .padding(.bottom, 8)

            Text(line)
                .font(Theme.sans(14, weight: .semibold))
                .foregroundStyle(Theme.foreground)

            if data.cancelled != true {
                HStack(spacing: 8) {
                    DelayBar(delaySec: delay)
                    Text(DelayFormat.sentence(delay))
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                    if let speed = data.vehicle?.speed {
                        Text("\(Int((speed * 3.6).rounded())) km/h")
                            .font(Theme.mono(11, weight: .regular))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .padding(.top, 6)
            }

            NoticeList(notices: data.notices?.map(\.text)).padding(.top, 10)
        }
    }

    private var stopList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(shownStops.enumerated()), id: \.offset) { index, stop in
                    if index > 0 { HairlineDivider(opacity: 0.6) }
                    stopRow(stop)
                }
            }
        }
    }

    private func stopRow(_ stop: TrainStop) -> some View {
        let late = stop.delaySec.map { abs($0) >= 60 } ?? false
        return HStack(spacing: 12) {
            Circle()
                .fill(stop.passed ? Theme.mutedForeground.opacity(0.5) : Theme.primary)
                .frame(width: 8, height: 8)
            Text(stop.name)
                .font(Theme.sans(12, weight: .medium))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            PlatformBadge(platform: stop.platform, changed: stop.platformChanged == true, predicted: stop.platformPredicted == true, mode: .rail, compact: true)
            HStack(spacing: 4) {
                Text(stop.schedDep)
                    .foregroundStyle(late ? Theme.mutedForeground : Theme.foreground)
                    .strikethrough(late)
                if late {
                    Text(BudapestClock.hm(stop.depUnix))
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.late)
                }
            }
            .font(Theme.mono(11, weight: .regular))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(stop.passed ? 0.55 : 1)
    }
}
