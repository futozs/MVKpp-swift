//
//  RouteTimetableView.swift
//  MVK++ Phone App
//

import SwiftUI

/// One route's board: the direction chips, the hour rows, and — once a run
/// is tapped — its details in a panel under the board, as on the web.
struct RouteTimetableView: View {
    @ObservedObject var model: TimetableModel

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var lineFavorites: LineFavoritesStore

    @State private var legendOpen = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if let route = model.selectedRoute {
                    header(route)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    if hasLegend && legendOpen, let table = model.table {
                        legend(table)
                    }
                    board
                    if let trip = model.selectedTrip, let table = model.table {
                        TimetableTripPanel(
                            trip: trip,
                            variantLabel: trip.variant.flatMap { variantLabels[$0] },
                            stops: table.stops,
                            routeShort: route.short,
                            mode: route.transitMode,
                            vehicle: selectedVehicle,
                            cancelled: model.cancelled.ids.contains(trip.tripId),
                            dateYmd: model.ymd,
                            journalEntry: model.journal.trips[trip.tripId],
                            nowSec: model.nowSec,
                            day: model.day,
                            maxHeight: geometry.size.height * 0.42,
                            onClose: { withAnimation(Theme.Motion.normalAnimation) { model.chooseTrip(nil) } },
                            onFocusTrip: { tripId, vehicleId in
                                navigation.focusTrip(tripId, vehicleId: vehicleId)
                                navigation.tab = .map
                            }
                        )
                        .id(trip.tripId)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(Theme.Motion.normalAnimation, value: model.selectedTrip?.tripId)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private func header(_ route: TimetableRoute) -> some View {
        let isFavorite = lineFavorites.contains(routeId: route.id, dir: model.selectedDir)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RouteTile(short: route.short, colorHex: route.color, textHex: route.text, size: .large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(route.long)
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    countsLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    lineFavorites.toggle(routeId: route.id, dir: model.selectedDir)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isFavorite ? Theme.primaryForeground : Theme.foreground)
                        .frame(width: 36, height: 36)
                        .background(isFavorite ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .strokeBorder(isFavorite ? Theme.primary : Theme.input, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(TimetablePressStyle())
                .sensoryFeedback(.selection, trigger: isFavorite)
                .accessibilityLabel(isFavorite ? "Levétel a kedvencekről" : "Hozzáadás a kedvencekhez")
            }

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(route.directions) { direction in
                    directionChip(direction)
                }
                if hasLegend {
                    Button {
                        withAnimation(Theme.Motion.fastAnimation) { legendOpen.toggle() }
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(legendOpen ? Theme.primary : Theme.mutedForeground)
                            .frame(width: 30, height: 30)
                            .background(legendOpen ? Theme.primary.opacity(0.12) : Theme.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                    .strokeBorder(legendOpen ? Theme.primary.opacity(0.6) : Theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jelmagyarázat")
                    .accessibilityHint("Mit jelentenek a pöttyök?")
                }
            }
            .padding(.top, 12)

            TimetableDayPicker(
                value: model.date,
                minIso: model.minIso,
                maxIso: model.maxIso,
                todayIso: TimetableModel.todayIso(),
                onShift: model.shiftDate(by:),
                onPick: model.setDate
            )
            .padding(.top, 10)

            if model.selectedTrip == nil {
                HereChip(stops: store.stops)
                    .padding(.top, 10)
            }
        }
        .padding(12)
        .background(Theme.card.opacity(0.7))
    }

    private var countsLine: some View {
        HStack(spacing: 8) {
            Text(model.table.map { "\($0.trips.count) menet" } ?? "betöltés…")
                .foregroundStyle(Theme.mutedForeground)

            if model.isTableOffline { OfflineTag(compact: true) }

            if liveTripCount > 0 {
                HStack(spacing: 6) {
                    LiveDot(size: 7)
                    Text("\(liveTripCount) elindult")
                }
                .fontWeight(.semibold)
                .foregroundStyle(Theme.live)
            }

            if cancelledTripCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "nosign").font(.system(size: 9, weight: .bold))
                    Text("\(cancelledTripCount) törölve")
                }
                .fontWeight(.semibold)
                .foregroundStyle(Theme.destructive)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
    }

    private func directionChip(_ direction: TimetableDirection) -> some View {
        let isOn = direction.dir == model.selectedDir
        return Button {
            model.selectDir(direction.dir)
        } label: {
            HStack(spacing: 8) {
                Text(direction.headsign.isEmpty ? "Irány \(direction.dir)" : direction.headsign)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
                Text("\(direction.tripsToday)")
                    .font(Theme.mono(10))
                    .padding(.horizontal, 4)
                    .background(
                        isOn ? Theme.primaryForeground.opacity(0.2) : Theme.muted,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
            }
            .foregroundStyle(isOn ? Theme.primaryForeground : Theme.mutedForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? Theme.primary : Theme.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(isOn ? Theme.primary : Theme.border, lineWidth: 1)
            )
            .mvkShadow(isOn ? Theme.Shadow.sm : Theme.Shadow.Level(radius: 0, y: 0, opacity: 0))
            .animation(Theme.Motion.fastAnimation, value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Only on request: on a phone the legend would cost the board two rows.
    private func legend(_ table: TimetableResponse) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let variants = table.variants, !variants.isEmpty {
                TimetableVariantLegend(variants: variants)
            } else {
                if table.trips.contains(where: \.headsignDiffers) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.early).frame(width: 6, height: 6)
                        Text("más célállomás, mint a viszonylat szokásos iránya (\(table.headsign))")
                    }
                }
                if table.trips.contains(where: \.deviates) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.mutedForeground).frame(width: 4, height: 4)
                        Text("a szokásos útvonalon kívüli megállót is érint (betérő)")
                    }
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.mutedForeground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
        .transition(.opacity)
    }

    // MARK: - Board

    private var board: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    boardContent(proxy: proxy)
                    if !model.tableLoading, !model.tableError, let variants = model.table?.variants, !variants.isEmpty {
                        TimetableVariantLegend(variants: variants)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func boardContent(proxy: ScrollViewProxy) -> some View {
        if model.tableLoading {
            Text("Menetrend betöltése…")
                .font(Theme.mono(12, weight: .regular))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if model.tableError {
            VStack(spacing: 12) {
                Text("A menetrend most nem tölthető be.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.mutedForeground)
                Button {
                    model.retryTable()
                } label: {
                    Text("Újra")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.input, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(TimetablePressStyle(cornerRadius: 6))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 40)
        } else if let table = model.table, !table.trips.isEmpty {
            TimetableGridView(
                trips: table.trips,
                vehicleByTrip: vehicleByTrip,
                cancelledTripIds: model.cancelled.ids,
                journal: model.journal.trips,
                selectedTripId: model.selectedTrip?.tripId,
                nowSec: model.nowSec,
                day: model.day,
                directionHeadsign: table.headsign,
                variantLabels: variantLabels,
                proxy: proxy,
                onSelectTrip: { trip in
                    withAnimation(Theme.Motion.normalAnimation) { model.toggleTrip(trip) }
                }
            )
        } else {
            Text(model.table?.note ?? "Ezen az irányon ezen a napon nem közlekedik járat.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 40)
        }
    }

    // MARK: - Derived

    private var hasLegend: Bool {
        model.table?.trips.contains { $0.deviates || $0.headsignDiffers } ?? false
    }

    private var variantLabels: [String: String] {
        Dictionary((model.table?.variants ?? []).map { ($0.code, $0.label) }, uniquingKeysWith: { first, _ in first })
    }

    private var vehicleByTrip: [String: LiveVehicle] {
        store.liveVehicles.reduce(into: [:]) { map, vehicle in
            guard !vehicle.tripId.isEmpty else { return }
            map[vehicle.tripId] = vehicle
        }
    }

    /// Trip ids repeat daily: a live bus can only belong to today's run.
    private var selectedVehicle: LiveVehicle? {
        guard model.day == .today, let trip = model.selectedTrip, !model.cancelled.ids.contains(trip.tripId) else { return nil }
        return vehicleByTrip[trip.tripId]
    }

    private var cancelledTripCount: Int {
        model.table?.trips.filter { model.cancelled.ids.contains($0.tripId) }.count ?? 0
    }

    private var liveTripCount: Int {
        guard model.day == .today else { return 0 }
        let vehicles = vehicleByTrip
        return model.table?.trips.filter {
            vehicles[$0.tripId] != nil
                && !model.cancelled.ids.contains($0.tripId)
                && !(model.journal.trips[$0.tripId]?.isWaitingAtStart ?? false)
        }.count ?? 0
    }
}

/// The lettered route variants explained: „A = Avas városközpont érintésével · 18 menet”.
struct TimetableVariantLegend: View {
    let variants: [TimetableVariant]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(variants) { variant in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(variant.code)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 4)
                        .background(Theme.early, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    (Text(variant.label).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.foreground)
                        + Text("  · \(variant.trips) menet").font(Theme.mono(10.5, weight: .regular)).foregroundColor(Theme.mutedForeground))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Betűjelek magyarázata")
    }
}
