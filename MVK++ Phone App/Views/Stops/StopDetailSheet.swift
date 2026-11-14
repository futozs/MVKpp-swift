//
//  StopDetailSheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// What is coming to one stop, over the map — the web app's
/// `stops/StopDetailDrawer`. Kept short: the rider still needs to see where
/// the bus is.
struct StopDetailSheet: View {
    let stop: Stop
    let isMonitored: Bool
    var onToggleMonitor: (String) -> Void
    var onFocusTrip: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var location: LocationProvider
    @StateObject private var model = StopArrivalsModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            content
        }
        .background(Theme.card.ignoresSafeArea())
        .task(id: stop.id) { await model.start(stopId: stop.id, stopName: stop.name, limit: 16) }
        .onDisappear { model.stop() }
        .accessibilityLabel("\(stop.name) indulásai")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(StopKind.label(stopId: stop.id, isStation: stop.station))
                        .font(Theme.mono(11, weight: .regular))
                    Text("·")
                    if let merged = model.response?.merged, merged.count >= 2 {
                        SharedStopTag(merged: merged)
                        Text("·")
                    }
                    if model.isOffline {
                        OfflineTag(compact: true)
                    } else if model.response?.rtError != nil {
                        Text("menetrendi")
                            .font(Theme.mono(11, weight: .regular))
                    } else {
                        HStack(spacing: 6) {
                            LiveDot()
                            Text("valós idejű")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.live)
                    }
                }
                .font(Theme.mono(11, weight: .regular))
                .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button {
                    onToggleMonitor(stop.id)
                } label: {
                    Image(systemName: isMonitored ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(isMonitored ? Theme.primaryForeground : Theme.foreground)
                        .background(
                            isMonitored ? Theme.primary : Theme.background,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .strokeBorder(isMonitored ? Theme.primary : Theme.input, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMonitored ? "\(stop.name) levétele a figyelőről" : "\(stop.name) felvétele a figyelőre")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Panel bezárása")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.error, model.arrivals.isEmpty {
            ScrollView {
                Text(error.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.destructive.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .strokeBorder(Theme.destructive.opacity(0.30), lineWidth: 1)
                    )
                    .padding(16)
            }
        } else if model.isLoading && model.arrivals.isEmpty {
            Text("Indulások lekérése…")
                .font(Theme.mono(12, weight: .regular))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            Spacer(minLength: 0)
        } else if model.arrivals.isEmpty {
            Text("Nincs közelgő indulás erről a megállóról.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        } else {
            TimelineView(.periodic(from: .now, by: 10)) { _ in
                let catchFor = CatchFor(stopLat: stop.lat, stopLon: stop.lon, position: location.position, now: RealtimeClient.shared.serverNow)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.arrivals.enumerated()), id: \.offset) { index, arrival in
                            if index > 0 {
                                Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                            }
                            ArrivalRowView(
                                arrival: arrival,
                                variant: .drawer,
                                list: model.arrivals,
                                verdict: catchFor.verdict(arrival)
                            ) { tripId, vehicleId in
                                onFocusTrip(tripId, vehicleId)
                            }
                        }
                    }
                }
            }
        }
    }
}
