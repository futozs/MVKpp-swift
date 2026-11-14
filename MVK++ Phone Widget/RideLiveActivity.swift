//
//  RideLiveActivity.swift
//  MVK++ Phone Widget
//
//  The ride in progress on the Lock Screen and in the Dynamic Island: the
//  next stop, the rider's stop with its expected time, stops to go, delay,
//  and „Leszálltam”.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            RideLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Theme.card.opacity(0.92))
                .activitySystemActionForegroundColor(Theme.foreground)
                .widgetURL(DeepLink.trip(tripId: context.state.tripId, vehicleId: context.state.vehicleId).url)
        } dynamicIsland: { context in
            let a = context.attributes
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        RideRouteBadge(route: a.route, color: a.color, text: a.text, size: 15)
                        Text(a.vehicleLabel).font(Theme.mono(11, weight: .bold)).foregroundStyle(Theme.primary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RideDelayText(state: s).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(a.headsign).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        RideStopsSummary(state: s)
                        RideProgressBar(progress: s.progress ?? 0, color: Theme.hex(a.color))
                        if !s.ended {
                            Button(intent: AlightRideIntent()) {
                                Label("Leszálltam", systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .tint(Theme.primary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                RideRouteBadge(route: a.route, color: a.color, text: a.text, size: 12)
            } compactTrailing: {
                RideCompactTrailing(state: s)
            } minimal: {
                RideRouteBadge(route: a.route, color: a.color, text: a.text, size: 10)
            }
            .keylineTint(Theme.hex(a.color))
            .widgetURL(DeepLink.trip(tripId: s.tripId, vehicleId: s.vehicleId).url)
        }
    }
}

private struct RideLockScreenView: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RideRouteBadge(route: attributes.route, color: attributes.color, text: attributes.text, size: 17)
                VStack(alignment: .leading, spacing: 1) {
                    if let leg = state.leg, leg > 1 {
                        Text("KÖRBEUTAZÁS · \(leg). MENET").font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.primary)
                    }
                    Text(attributes.headsign).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.foreground).lineLimit(1)
                    HStack(spacing: 8) {
                        Text(attributes.vehicleLabel).font(Theme.mono(11, weight: .bold)).foregroundStyle(Theme.primary)
                        if let speed = state.speedKmh, !state.ended {
                            Text("\(speed) km/h").font(Theme.mono(11, weight: .regular)).foregroundStyle(Theme.mutedForeground)
                        }
                    }
                }
                Spacer(minLength: 8)
                RideDelayText(state: state)
            }
            RideStopsSummary(state: state)
            RideProgressBar(progress: state.progress ?? 0, color: Theme.hex(attributes.color))
            if !state.ended {
                Button(intent: AlightRideIntent()) {
                    Label("Leszálltam", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .foregroundStyle(Theme.primaryForeground)
            }
        }
        .padding(16)
    }
}

private struct RideStopsSummary: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if state.ended {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primary)
                Text("Utazás elmentve\(state.destName.map { " · \($0)" } ?? "")")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
            }
        } else if state.phase == .turn {
            VStack(alignment: .leading, spacing: 2) {
                Text("Körbeutazás · \(state.turnName ?? "")").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primary)
                Text(state.destName.map { "Leszállás: \($0)" } ?? "Maradj ülve — a busz hamarosan továbbindul")
                    .font(.system(size: 13)).foregroundStyle(Theme.foreground).lineLimit(1)
            }
        } else if state.phase == .setup {
            Text("Hol szállsz le? Nyisd meg az appot, és válaszd ki.")
                .font(.system(size: 13)).foregroundStyle(Theme.mutedForeground)
        } else {
            HStack(alignment: .top, spacing: 12) {
                if let next = state.nextStopName {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("KÖVETKEZŐ").font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.mutedForeground)
                        Text(next).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                        if let at = state.nextStopAt {
                            Text(at, style: .time).font(Theme.mono(12, weight: .regular)).foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let dest = state.destName {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("LESZÁLLÁS").font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.primary)
                        Text(dest).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                        HStack(spacing: 6) {
                            if let left = state.stopsLeft { Text("még \(left) megálló") }
                            if let at = state.destAt {
                                Text(at, style: .time).font(Theme.mono(12, weight: .bold)).foregroundStyle(Theme.foreground)
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.mutedForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

private struct RideCompactTrailing: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        if state.ended {
            Image(systemName: "checkmark").foregroundStyle(Theme.primary)
        } else if let at = state.destAt, at > .now {
            Text(timerInterval: Date.now...at, countsDown: true)
                .font(Theme.mono(12, weight: .bold))
                .monospacedDigit()
                .frame(maxWidth: 52)
                .foregroundStyle(Theme.primary)
        } else if let left = state.stopsLeft {
            Text("\(left)").font(Theme.mono(13, weight: .bold)).foregroundStyle(Theme.primary)
        } else {
            Image(systemName: "bus.fill").foregroundStyle(Theme.primary)
        }
    }
}

private struct RideDelayText: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        Text(DelayFormat.label(state.delaySec))
            .font(Theme.mono(12, weight: .semibold))
            .foregroundStyle(DelayFormat.tone(state.delaySec))
    }
}

private struct RideProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.muted)
                Capsule().fill(color).frame(width: max(6, proxy.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 6)
    }
}

private struct RideRouteBadge: View {
    let route: String
    let color: String
    let text: String
    let size: CGFloat

    var body: some View {
        Text(route)
            .font(.system(size: size, weight: .heavy))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(Theme.hex(text, fallback: .white))
            .padding(.horizontal, size * 0.45)
            .padding(.vertical, size * 0.15)
            .background(Theme.hex(color), in: RoundedRectangle(cornerRadius: size * 0.5, style: .continuous))
            .fixedSize()
    }
}
