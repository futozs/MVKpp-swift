//
//  RouteTimetableView.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

/// One route's board: pick a direction, read the hours, tap a departure.
struct RouteTimetableView: View {
    let route: TimetableRoute
    let initialDir: String?
    @ObservedObject var model: TimetableModel

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var lineFavorites: LineFavoritesStore

    @State private var dir = ""
    @State private var table: TimetableResponse?
    @State private var isTableOffline = false
    @State private var isLoading = false
    @State private var selectedTrip: TimetableTrip?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    content
                } header: {
                    header
                }
            }
        }
        .background(AppBackground())
        .navigationTitle(route.short)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    lineFavorites.toggle(routeId: route.id, dir: dir)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .tint(isFavorite ? Theme.primary : Theme.mutedForeground)
                .accessibilityLabel(isFavorite ? "Levétel a kedvencekről" : "Hozzáadás a kedvencekhez")
            }
        }
        .sheet(item: $selectedTrip) { trip in
            if let table {
                TripDetailSheet(
                    trip: trip,
                    stops: table.stops,
                    routeShort: route.short,
                    vehicle: vehicleByTrip[trip.tripId],
                    isCancelled: model.cancelledTripIds.contains(trip.tripId),
                    journalEntry: model.journal[trip.tripId],
                    nowSec: model.nowSec,
                    day: model.day,
                    onFocusTrip: { tripId, vehicleId in
                        navigation.focusTrip(tripId, vehicleId: vehicleId)
                        navigation.tab = .map
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .task {
            if dir.isEmpty { dir = initialDir ?? defaultDir }
            await loadTable()
        }
        .onChange(of: dir) { _, _ in Task { await loadTable() } }
        .onChange(of: model.date) { _, _ in Task { await loadTable() } }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RouteTile(short: route.short, colorHex: route.color, textHex: route.text, size: .large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(route.long)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Text(table.map { "\($0.trips.count) menet" } ?? "betöltés…")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.mutedForeground)

                        // Live decoration — which run has left, which is
                        // cancelled — needs the network. Offline the board is
                        // complete but static, and saying so is the difference
                        // between "nothing is cancelled" and "we cannot know".
                        if isTableOffline { OfflineTag(compact: true) }

                        if liveTripCount > 0 {
                            HStack(spacing: 5) {
                                LiveDot(size: 7)
                                Text("\(liveTripCount) elindult")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.live)
                            }
                        }

                        if cancelledTripCount > 0 {
                            Label("\(cancelledTripCount) törölve", systemImage: "nosign")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.destructive)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if route.directions.count > 1 || !route.directions.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(route.directions) { direction in
                        directionChip(direction)
                    }
                }
            }

            legend
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func directionChip(_ direction: TimetableDirection) -> some View {
        let isOn = direction.dir == dir
        return Button {
            dir = direction.dir
        } label: {
            HStack(spacing: 6) {
                Text(direction.headsign.isEmpty ? "Irány \(direction.dir)" : direction.headsign)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(direction.tripsToday)")
                    .font(Theme.mono(10))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        isOn ? Color.black.opacity(0.2) : Theme.muted,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
            }
            .foregroundStyle(isOn ? Theme.primaryForeground : Theme.mutedForeground)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                isOn ? Theme.primary : Theme.secondary,
                in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(isOn ? Theme.primary : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Explains the two dots the grid puts on chips, but only when this board
    /// actually has runs carrying them.
    @ViewBuilder
    private var legend: some View {
        let hasHeadsignDiff = table?.trips.contains(where: \.headsignDiffers) ?? false
        let hasDeviation = table?.trips.contains(where: \.deviates) ?? false

        if hasHeadsignDiff || hasDeviation {
            VStack(alignment: .leading, spacing: 3) {
                if hasHeadsignDiff, let headsign = table?.headsign {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.early).frame(width: 6, height: 6)
                        Text("más célállomás, mint a viszonylat szokásos iránya (\(headsign))")
                    }
                }
                if hasDeviation {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.mutedForeground).frame(width: 4, height: 4)
                        Text("a szokásos útvonalon kívüli megállót is érint (betérő)")
                    }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.mutedForeground)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Text("Menetrend betöltése…")
                .font(Theme.mono(12, weight: .regular))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let table, !table.trips.isEmpty {
            TimetableGridView(
                trips: table.trips,
                vehicleByTrip: vehicleByTrip,
                cancelledTripIds: model.cancelledTripIds,
                selectedTripId: selectedTrip?.tripId,
                nowSec: model.nowSec,
                day: model.day,
                onSelectTrip: { trip in selectedTrip = trip }
            )
        } else {
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
        }
    }

    /// "Nem közlekedik" and "we could not find out" look identical on an empty
    /// board, so they are never worded the same.
    private var emptyMessage: String {
        if let note = table?.note { return note }
        if table == nil {
            return OfflineScheduleStore.hasSchedule(for: TimetableModel.isoToYmd(model.date))
                ? "Ezen az irányon ezen a napon nem közlekedik járat."
                : "Nincs kapcsolat, és erre a napra nincs letöltött menetrend."
        }
        return "Ezen az irányon ezen a napon nem közlekedik járat."
    }

    // MARK: - Data

    private func loadTable() async {
        guard !dir.isEmpty else { return }
        isLoading = true
        selectedTrip = nil
        defer { isLoading = false }

        let ymd = TimetableModel.isoToYmd(model.date)
        do {
            table = try await APIClient.shared.timetable(routeId: route.id, dir: dir, date: ymd)
            isTableOffline = false
        } catch {
            // Stored verbatim at download time, so this is the same board the
            // gateway would have sent — decoded by the same type.
            table = OfflineScheduleStore.timetable(routeId: route.id, dir: dir, ymd: ymd)
            isTableOffline = table != nil
        }
    }

    /// Opens on a direction that actually runs today rather than a dead one.
    private var defaultDir: String {
        (route.directions.first { $0.tripsToday > 0} ?? route.directions.first)?.dir ?? ""
    }

    private var isFavorite: Bool {
        lineFavorites.contains(routeId: route.id, dir: dir)
    }

    private var vehicleByTrip: [String: LiveVehicle] {
        store.liveVehicles.reduce(into: [:]) { map, vehicle in
            guard !vehicle.tripId.isEmpty else { return }
            map[vehicle.tripId] = vehicle
        }
    }

    private var cancelledTripCount: Int {
        table?.trips.filter { model.cancelledTripIds.contains($0.tripId) }.count ?? 0
    }

    private var liveTripCount: Int {
        guard model.day == .today else { return 0 }
        return table?.trips.filter {
            vehicleByTrip[$0.tripId] != nil && !model.cancelledTripIds.contains($0.tripId)
        }.count ?? 0
    }
}
