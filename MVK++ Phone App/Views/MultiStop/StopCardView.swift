//
//  StopCardView.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

/// One watched stop: the next departure in full, then the ones after it.
///
/// The split is deliberate. A rider glancing at their phone wants one number —
/// how long until the next bus — and everything else is context they only read
/// if that number is bad news.
struct StopCardView: View {
    let stop: Stop
    var distanceKm: Double?
    var isNearest = false
    var onRemove: (String) -> Void
    var onFocusMap: (Stop, String?, String?) -> Void

    @EnvironmentObject private var favorites: FavoritesStore

    @StateObject private var model = StopArrivalsModel()
    @State private var isNotifyOpen = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            nextDeparture
            Divider().overlay(Theme.border)
            laterDepartures
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .strokeBorder(isNearest ? Theme.primary : Theme.border, lineWidth: isNearest ? 2 : 1)
        )
        .mvkShadow(Theme.Shadow.lg)
        .task(id: stop.id) { await model.start(stopId: stop.id, stopName: stop.name, limit: 8) }
        .onDisappear { model.stop() }
        .sheet(isPresented: $isNotifyOpen) {
            StopNotifySheet(stop: stop, arrivals: model.arrivals)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let distanceKm {
                        Text(Geo.formatDistance(distanceKm))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.foreground)
                    }
                    Text(stop.id)
                        .font(Theme.mono(11, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                    if isOnWatch {
                        Label("órán", systemImage: "applewatch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                // Puts this stop on the Watch's Smart Stack and the widget.
                // Only one stop can hold that slot, so tapping it again clears it.
                iconButton(
                    isOnWatch ? "applewatch.watchface" : "applewatch",
                    label: isOnWatch ? "Levétel az óra widgetjéről" : "Megjelenítés az óra widgetjén",
                    tint: isOnWatch ? Theme.primary : nil
                ) {
                    favorites.widgetStopId = isOnWatch ? nil : stop.id
                }

                iconButton("scope", label: "Megjelenítés a térképen") {
                    onFocusMap(stop, nil, nil)
                }
                iconButton(
                    NotificationCenterStore.shared.hasWatch(stopId: stop.id) ? "bell.badge.fill" : "bell",
                    label: "Értesítés beállítása",
                    tint: NotificationCenterStore.shared.hasWatch(stopId: stop.id) ? Theme.primary : nil
                ) {
                    isNotifyOpen = true
                }
                iconButton("trash", label: "Levétel a figyelőről", tint: Theme.destructive) {
                    onRemove(stop.id)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func iconButton(
        _ systemName: String,
        label: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? Theme.mutedForeground)
        .accessibilityLabel("\(label) — \(stop.name)")
    }

    private var isOnWatch: Bool { favorites.widgetStopId == stop.id }

    // MARK: - Next departure

    @ViewBuilder
    private var nextDeparture: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.errorMessage, model.arrivals.isEmpty {
                ErrorNotice(message: error)
            } else if model.isLoading && model.arrivals.isEmpty {
                Text("Indulások lekérése…")
                    .font(Theme.mono(12, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let next = model.arrivals.first {
                HStack {
                    Text("KÖVETKEZŐ")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.mutedForeground)
                    Spacer()
                    if model.isOffline {
                        OfflineTag(compact: true)
                    } else {
                        LiveTag(live: next.live)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    RouteTile(short: next.route, colorHex: next.color, textHex: next.text, size: .large)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(next.headsign)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(next.time)
                                .font(Theme.mono(12, weight: .regular))
                                .foregroundStyle(Theme.mutedForeground)
                            DelayBar(delaySec: next.delaySec)
                        }
                    }

                    Spacer(minLength: 4)

                    CountdownView(etaMin: next.etaMin)
                }

                VehicleTrackView(
                    vehicle: next.vehicle,
                    progressDesc: next.progressDesc,
                    onTrack: next.vehicle == nil ? nil : {
                        onFocusMap(stop, next.tripId, next.vehicle?.id)
                    }
                )
            } else {
                Text("Ebben az órában nincs több indulás.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted.opacity(0.3))
    }

    // MARK: - Later departures

    private var laterDepartures: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let rest = Array(model.arrivals.dropFirst().prefix(5))
                if rest.isEmpty {
                    if !model.arrivals.isEmpty {
                        Text("Nincs több ismert indulás.")
                            .font(.caption)
                            .foregroundStyle(Theme.mutedForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                } else {
                    ForEach(rest) { arrival in
                        ArrivalRowView(arrival: arrival) { tripId, vehicleId in
                            onFocusMap(stop, tripId, vehicleId)
                        }
                        .padding(.horizontal, 14)
                        Divider().overlay(Theme.border.opacity(0.6))
                    }
                }
            }
        }
    }
}
