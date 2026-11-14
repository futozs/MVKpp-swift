//
//  TripTimetable.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

/// The followed vehicle's timetable (`TripTimetable.tsx`): every stop with
/// its timetabled and expected time, platform, the passed ones faded, the
/// next highlighted, a bar for how far the run has got, and MÁV's notices.
/// On a phone (trains only) it sits folded above the card, around the next
/// stations, and opens to the whole list.
struct TripTimetable: View {
    let tripId: String

    @StateObject private var model = TripTimetableModel()
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let liveShownS = 60
    private static let compactBefore = 1
    private static let compactAfter = 2

    private var rail: Bool { TransitFeed.of(id: tripId) == .rail }
    private var unit: String { rail ? "állomás" : "megálló" }

    var body: some View {
        Group {
            if model.data == nil, model.error == nil {
                shell {
                    Text("A menetrend betöltése…")
                        .font(Theme.mono(12, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            } else if model.data?.found == false {
                EmptyView()
            } else {
                shell { content }
            }
        }
        .task(id: tripId) { await model.run(tripId: tripId) }
    }

    private func shell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(rail ? "A követett vonat menetrendje" : "A követett járat menetrendje")
    }

    private var stops: [TrainStop] { model.data?.found == true ? model.data?.stops ?? [] : [] }
    private var nextIdx: Int { stops.firstIndex { !$0.passed } ?? -1 }
    private var arrived: Bool { !stops.isEmpty && nextIdx < 0 }
    private var passedCount: Int { arrived ? stops.count : max(0, nextIdx) }

    private func inCompact(_ i: Int) -> Bool {
        let from = arrived ? stops.count - 1 - Self.compactBefore : max(0, nextIdx - Self.compactBefore)
        return arrived ? i >= from : i >= from && i <= nextIdx + Self.compactAfter
    }

    @ViewBuilder
    private var content: some View {
        let hiddenCount = stops.indices.filter { !inCompact($0) }.count
        HStack(spacing: 8) {
            Image(systemName: "list.number")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text("Menetrend")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.foreground)
            if !stops.isEmpty {
                Text("\(passedCount)/\(stops.count) \(unit)")
                    .font(Theme.mono(11, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityLabel("\(passedCount) \(unit) elhagyva")
            }
            Spacer(minLength: 8)
            if model.data?.cancelled == true {
                Text("TÖRÖLVE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.destructive)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.destructive.opacity(0.5)))
            }
            if hiddenCount > 0 {
                Button {
                    withAnimation(Theme.Motion.normalAnimation) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Kevesebb" : "Mind")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

        if stops.count > 1 {
            let ratio = arrived ? 1 : nextIdx <= 0 ? 0 : (Double(nextIdx) - 0.5) / Double(stops.count - 1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.border.opacity(0.6))
                    Rectangle().fill(Theme.primary)
                        .frame(width: proxy.size.width)
                        .scaleEffect(x: min(1, max(0, ratio)), anchor: .leading)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: ratio)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }

        if let error = model.error {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.late)
                Text("\(Text("Hiba, újrapróbálom…").fontWeight(.semibold).foregroundStyle(Theme.foreground)) \(error.reason)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.late.opacity(0.10))
        }

        if let notices = model.data?.notices?.map(\.text), !notices.isEmpty {
            NoticeList(notices: notices, compact: !expanded)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        }

        if !stops.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                            if expanded || inCompact(i) {
                                row(stop, index: i).id(i)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: expanded ? UIScreen.main.bounds.height * 0.34 : nil)
                .fixedSize(horizontal: false, vertical: !expanded)
                .onChange(of: nextIdx) { _, _ in scroll(proxy) }
                .onChange(of: expanded) { _, _ in scroll(proxy) }
                .onAppear { scroll(proxy, animated: false) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target = nextIdx < 0 ? stops.count - 1 : max(0, nextIdx - 1)
        if animated, !reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
        } else {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func row(_ s: TrainStop, index i: Int) -> some View {
        let isNext = i == nextIdx
        let terminus = i == stops.count - 1
        let sched = terminus ? s.schedArr : s.schedDep
        let liveUnix = terminus ? s.arrUnix : s.depUnix
        let showLive = !s.passed && (s.delaySec.map { abs($0) >= Self.liveShownS } ?? false)
        let dwell = i > 0 && !terminus && s.schedArr != s.schedDep
        let inDone = i > 0 && (s.passed || isNext)
        let outDone = !terminus && s.passed

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(sched)
                    .font(Theme.mono(11.5, weight: s.passed ? .regular : .semibold))
                    .foregroundStyle(s.passed || showLive ? Theme.mutedForeground : Theme.foreground)
                    .strikethrough(showLive)
                if showLive {
                    Text(BudapestClock.hm(liveUnix))
                        .font(Theme.mono(11.5, weight: .bold))
                        .foregroundStyle(DelayFormat.tone(s.delaySec))
                }
            }
            .frame(width: 42, alignment: .trailing)
            .padding(.vertical, 6)

            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(i == 0 ? AnyShapeStyle(Color.clear) : inDone
                            ? (isNext ? AnyShapeStyle(LinearGradient(colors: [Theme.primary, Theme.primary.opacity(0.25)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.primary))
                            : AnyShapeStyle(Theme.border))
                        .frame(width: 2)
                    Rectangle()
                        .fill(terminus ? Theme.clear : outDone ? Theme.primary : Theme.border)
                        .frame(width: 2)
                }
                dot(isNext: isNext, passed: s.passed, square: i == 0 || terminus)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(s.name)
                    .font(.system(size: 12.5, weight: isNext ? .bold : s.passed ? .regular : .medium))
                    .foregroundStyle(s.passed ? Theme.mutedForeground : Theme.foreground)
                    .lineLimit(1)
                if isNext || dwell {
                    HStack(spacing: 6) {
                        if isNext {
                            Text(i == 0 ? "INDUL" : "KÖVETKEZŐ")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.primary)
                        }
                        if dwell {
                            Text("érk. \(s.schedArr)")
                                .font(Theme.mono(10.5, weight: .regular))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)

            PlatformBadge(platform: s.platform, changed: s.platformChanged == true, predicted: s.platformPredicted == true, mode: rail ? .rail : .coach, compact: true)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isNext ? .isSelected : [])
    }

    @ViewBuilder
    private func dot(isNext: Bool, passed: Bool, square: Bool) -> some View {
        let shape = square && !isNext
            ? AnyShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            : AnyShape(Circle())
        if isNext {
            ZStack {
                PulseRing()
                Circle().fill(Theme.primary)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                    .overlay(Circle().stroke(Theme.primary, lineWidth: 2).padding(-2))
            }
            .frame(width: 12, height: 12)
        } else if passed {
            shape.fill(Theme.primary.opacity(0.7)).frame(width: 8, height: 8)
        } else {
            shape.fill(Theme.card)
                .frame(width: 10, height: 10)
                .overlay(shape.stroke(Theme.mutedForeground.opacity(0.45), lineWidth: 2))
        }
    }
}

private struct PulseRing: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Theme.primary.opacity(0.4))
            .scaleEffect(on ? 2 : 1)
            .opacity(on ? 0 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

private extension Theme {
    static let clear = Color.clear
}

/// Polls `/engine/transit/trip` every 15 s while visible.
@MainActor
final class TripTimetableModel: ObservableObject {
    @Published private(set) var data: TrainDetailResponse?
    @Published private(set) var error: FriendlyError?

    func run(tripId: String) async {
        data = nil
        error = nil
        while !Task.isCancelled {
            do {
                let response = try await APIClient.shared.tripDetail(tripId: tripId)
                guard !Task.isCancelled else { return }
                data = response
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = FriendlyError(error)
            }
            try? await Task.sleep(for: .seconds(15))
        }
    }
}
