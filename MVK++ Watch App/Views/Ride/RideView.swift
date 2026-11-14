//
//  RideView.swift
//  MVK++ Watch App
//

import SwiftUI

/// The ride in progress: the next stop and when the bus gets there, how many
/// stops are left to the rider's own, and "Leszálltam".
struct RideView: View {
    @EnvironmentObject private var link: WatchLink
    @EnvironmentObject private var rides: RideController
    @EnvironmentObject private var router: WatchRouter

    var body: some View {
        Group {
            if let ride = link.ride {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        RideHeader(ride: ride)
                        if ride.ended {
                            arrived(ride)
                        } else {
                            nextStop(ride)
                            RideProgress(ride: ride)
                            actions(ride)
                        }
                        if let note = rides.note {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                }
                .containerBackground(ride.accentColor.gradient.opacity(0.45), for: .navigation)
            } else if rides.awaitingPhone {
                ProgressView("A telefon indítja az utat…")
            } else {
                ContentUnavailableView {
                    Label("Nincs aktív utazás", systemImage: "ticket")
                } description: {
                    Text("Egy induló járatnál húzd jobbra a sort, vagy a térképen koppints a buszra.")
                } actions: {
                    Button("Felszálltam") { router.show(.boardPicker) }
                }
            }
        }
        .navigationTitle("Utazás")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func nextStop(_ ride: WatchRideSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ride.isGetOffNext ? "Itt szállsz le" : "Következő megálló")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ride.isGetOffNext ? Theme.amber400 : Theme.mutedForeground)
            HStack(alignment: .firstTextBaseline) {
                Text(ride.nextStopName ?? "A busz helyét keresem…")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if let due = ride.nextStopDate {
                    RideCountdown(due: due)
                }
            }
        }
    }

    private func actions(_ ride: WatchRideSnapshot) -> some View {
        VStack(spacing: 6) {
            Button(role: .destructive) {
                Task { await rides.end() }
            } label: {
                Label("Leszálltam", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button {
                router.push(.trip(TripRef(ride: ride)))
            } label: {
                Label("Térképen", systemImage: "map")
            }
        }
    }

    private func arrived(_ ride: WatchRideSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Megérkeztél", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.live)
            if let stop = ride.destinationStopName {
                Text(stop)
                    .font(.footnote)
            }
            Button("Bezárás") {
                rides.dismissEnded()
                router.popToRoot()
            }
        }
    }
}

struct RideHeader: View {
    let ride: WatchRideSnapshot

    var body: some View {
        HStack(spacing: 7) {
            RouteTile(short: ride.route, colorHex: ride.color, textHex: ride.textColor, size: .large)
            VStack(alignment: .leading, spacing: 1) {
                Text(ride.headsign)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                Text(DelayFormat.label(ride.delaySec))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DelayFormat.tone(ride.delaySec))
            }
        }
    }
}

/// How far along the rider's own leg the bus is.
struct RideProgress: View {
    let ride: WatchRideSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Gauge(value: ride.progress ?? 0) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(ride.accentColor)
            HStack {
                if let left = ride.stopsLeft {
                    Text(left == 1 ? "1 megálló" : "\(left) megálló")
                        .font(Theme.mono(11, weight: .bold))
                }
                Spacer(minLength: 4)
                if let destination = ride.destinationStopName {
                    Text(destination)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Minutes to the next stop, ticking on its own between updates.
struct RideCountdown: View {
    let due: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let minutes = max(0, Int((due.timeIntervalSince(context.date) / 60).rounded(.up)))
            if minutes == 0 {
                Text("most")
                    .font(Theme.mono(13, weight: .heavy))
                    .foregroundStyle(Theme.primary)
            } else {
                CountdownView(etaMin: minutes, style: .compact)
            }
        }
    }
}

/// The ride, on top of the Figyelő list.
struct RideBanner: View {
    let ride: WatchRideSnapshot
    @EnvironmentObject private var router: WatchRouter

    var body: some View {
        Button {
            router.push(.ride)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 7) {
                    RouteTile(short: ride.route, colorHex: ride.color, textHex: ride.textColor, size: .medium)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ride.ended ? "Megérkeztél" : (ride.isGetOffNext ? "Itt szállsz le" : "Következő megálló"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ride.isGetOffNext ? Theme.amber400 : Theme.mutedForeground)
                        Text(ride.ended ? (ride.destinationStopName ?? ride.headsign) : (ride.nextStopName ?? ride.headsign))
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 2)
                    if let due = ride.nextStopDate, !ride.ended {
                        RideCountdown(due: due)
                    }
                }
                if !ride.ended {
                    RideProgress(ride: ride)
                }
            }
            .glassCard(tint: ride.accentColor, cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}
