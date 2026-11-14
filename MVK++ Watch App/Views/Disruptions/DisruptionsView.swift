//
//  DisruptionsView.swift
//  MVK++ Watch App
//

import SwiftUI

/// Mai zavarok: every trip dropping out today — MVK's own cancellations, the
/// ones missing right now and the ones nobody saw leave — with the run that
/// replaces each. The rider's watched stops come first.
struct DisruptionsView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var data: Disruptions?
    @State private var error: String?
    @State private var filter: DisruptionKind?
    @State private var showsPast = false

    var body: some View {
        List {
            if let data {
                counts(data)
                    .listRowBackground(Color.clear)

                if !data.nearStops.isEmpty {
                    Text("A figyelt megállóidnál: \(data.nearStops.map(\.name).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(Theme.mutedForeground)
                        .listRowBackground(Color.clear)
                }

                if trips(data).isEmpty {
                    Text(filter == nil ? "Most nincs kimaradó menet." : "Ebből most nincs.")
                        .font(.footnote)
                        .foregroundStyle(Theme.mutedForeground)
                        .listRowBackground(Color.clear)
                }
                ForEach(trips(data)) { trip in
                    DisruptionRow(trip: trip)
                }
                if !showsPast, data.trips.contains(where: { !$0.upcoming }) {
                    Button("Korábbiak is") { showsPast = true }
                        .font(.footnote)
                }
            } else if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.late)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Mai zavarok")
        .containerBackground(Theme.late.gradient.opacity(0.25), for: .navigation)
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func counts(_ data: Disruptions) -> some View {
        HStack(spacing: 4) {
            ForEach(DisruptionKind.allCases, id: \.self) { kind in
                Button {
                    filter = filter == kind ? nil : kind
                } label: {
                    VStack(spacing: 0) {
                        Text("\(data.count(kind))")
                            .font(Theme.mono(16, weight: .heavy))
                            .foregroundStyle(kind.tone)
                        Text(kind.short)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(filter == kind ? kind.tone.opacity(0.25) : Theme.card.opacity(0.8))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.label): \(data.count(kind))")
            }
        }
    }

    private func trips(_ data: Disruptions) -> [DisruptionTrip] {
        data.trips
            .filter { showsPast || $0.upcoming || $0.kind == .missing }
            .filter { filter == nil || $0.kind == filter }
            .sorted { ($0.near != nil ? 0 : 1, $0.depS) < ($1.near != nil ? 0 : 1, $1.depS) }
    }

    private func load() async {
        do {
            data = try await APIClient.shared.disruptions(near: Array(favorites.stopIds.prefix(6)))
            error = nil
        } catch {
            if data == nil { self.error = "A mai menetrend még töltődik, vagy nincs kapcsolat." }
        }
    }
}

private struct DisruptionRow: View {
    let trip: DisruptionTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                RouteTile(short: trip.route, colorHex: trip.color, textHex: trip.text, size: .medium)
                Text(trip.depTime)
                    .font(Theme.mono(13, weight: .bold))
                Spacer(minLength: 2)
                if let kind = trip.kind {
                    Label(kind.short, systemImage: kind.icon)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(kind.tone)
                }
            }
            Text(trip.headsign)
                .font(.system(size: 12))
                .lineLimit(2)
            if let near = trip.near {
                Text("\(near.name) \(near.time)")
                    .font(.caption2)
                    .foregroundStyle(Theme.primary)
            }
            if let replacement = trip.replacement {
                Text("Helyette \(replacement.depTime) (+\(replacement.gapMin) perc)")
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .opacity(trip.upcoming || trip.kind == .missing ? 1 : 0.55)
    }
}
