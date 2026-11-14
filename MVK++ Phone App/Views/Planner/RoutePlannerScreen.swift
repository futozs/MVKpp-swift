//
//  RoutePlannerScreen.swift
//  MVK++ Phone App
//

import SwiftUI

/// The route planner on our own `/engine/plan`. One request brings the
/// timetable itinerary and beside it: for a past day the measured departure
/// and arrival (copyable as proof), for today and later the expected lateness
/// (live or from earlier measurements) and the risk of each transfer.
struct RoutePlannerScreen: View {
    @EnvironmentObject private var store: TransitStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var model = RoutePlannerModel()
    @State private var resultsVisible = true

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Útvonaltervező")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(-0.3)
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 4)
                            .accessibilityAddTraits(.isHeader)

                        PlannerForm(model: model)

                        results
                            .id("results")
                            .onScrollVisibilityChange(threshold: 0.01) { resultsVisible = $0 }
                    }
                    .frame(maxWidth: 768)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.isLoading) { _, loading in
                    guard loading, !resultsVisible else { return }
                    if reduceMotion {
                        proxy.scrollTo("results", anchor: .top)
                    } else {
                        withAnimation(Theme.Motion.normalAnimation) { proxy.scrollTo("results", anchor: .top) }
                    }
                }
            }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: store.stops.count) { model.updateCatalog(store.stops) }
        .onChange(of: scenePhase) { _, phase in model.isActive = phase == .active }
    }

    @ViewBuilder
    private var results: some View {
        switch model.result {
        case .idle:
            Color.clear.frame(height: 1)
        case .loading:
            PlannerResultsSkeleton()
                .accessibilityLabel("Keresés…")
        case .error(let message):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.destructive.opacity(0.30), lineWidth: 1))
        case .done(let plan):
            PlannerResults(plan: plan, emptyHint: model.travel.emptyHint)
                .transition(.opacity)
        }
    }
}

private struct PlannerResults: View {
    let plan: JourneyPlanResponse
    let emptyHint: String?

    private static let modeTag: [JourneyMode: String] = [.past: "Mért adatok", .now: "Élő", .future: "Előrejelzés"]

    private static let modeNote: [JourneyMode: String] = [
        .past: "A menetrendet a járművek mért GPS-adataival vetjük össze: így ment valójában.",
        .now: "Ahol a jármű már úton van, az élő késésével számolunk, a többinél a korábbi mérésekkel.",
        .future: "A várható késés az elmúlt 90 nap hasonló napjain, ugyanebben a napszakban mért adatokból jön. A „rossz esetben” értéknél a mérések 85%-a nem volt rosszabb.",
    ]

    var body: some View {
        let when = plan.arriveBy
            ? "\(PlannerFormat.hm(plan.at))-ig érkezéssel"
            : "\(PlannerFormat.hm(plan.at)) utáni indulással"
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(plan.from.name) → \(plan.to.name)")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 11))
                        Text("\(PlannerFormat.longDate(PlannerFormat.localIsoDate(plan.at))) · \(when)")
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.mutedForeground)
                }
                Spacer(minLength: 0)
                modeTag
            }
            .padding(.horizontal, 4)

            if let fallback = plan.schedule.fallback {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13))
                        .foregroundStyle(PlannerAmber.a300)
                        .padding(.top, 1)
                    Text("Az MVK erre a napra nem adott ki menetrendet, ezért \(PlannerFormat.dateAdjective(fallback)) menetrend alapján terveztünk. A valóságban eltérhet.")
                        .font(.system(size: 12))
                        .foregroundStyle(PlannerAmber.a200)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PlannerAmber.a400.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(PlannerAmber.a400.opacity(0.35), lineWidth: 1))
            }

            if plan.trips.isEmpty {
                VStack(spacing: 4) {
                    Text("Ebben az időpontban nincs kapcsolat a két hely között.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text(emptyHint ?? "Éjszaka és hétvégén kevesebb járat közlekedik próbálj másik időpontot.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            } else {
                Text(Self.modeNote[plan.mode] ?? "")
                    .font(.system(size: 11))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                VStack(spacing: 12) {
                    ForEach(Array(plan.trips.enumerated()), id: \.offset) { index, trip in
                        PlannerTripCard(plan: plan, trip: trip, defaultOpen: index == 0)
                            .id("\(plan.at)-\(trip.start)-\(index)")
                    }
                }
            }
        }
    }

    private var modeTag: some View {
        let live = plan.mode == .now
        return HStack(spacing: 6) {
            if live {
                LiveDot()
            } else {
                Image(systemName: plan.mode == .past ? "clock.arrow.circlepath" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(Self.modeTag[plan.mode] ?? "")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(live ? Theme.live : Theme.foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(live ? Theme.live.opacity(0.10) : Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(live ? Theme.live.opacity(0.4) : Theme.border, lineWidth: 1)
        )
        .fixedSize()
    }
}

private struct PlannerResultsSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        bar(width: 144, height: 24)
                        Spacer()
                        bar(width: 56, height: 16)
                    }
                    HStack(spacing: 6) {
                        bar(width: 36, height: 20)
                        bar(width: 36, height: 20)
                    }
                    bar(width: 208, height: 14)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
        }
        .opacity(dim ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height > 16 ? Theme.Radius.md : 4, style: .continuous)
            .fill(Theme.muted)
            .frame(width: width, height: height)
    }
}
