//
//  MultiStopScreen.swift
//  MVK++ Phone App
//

import SwiftUI

/// The Figyelő — the web app's `MultiStopDashboard` at phone width: the
/// watched stops, relations and train numbers as a swipeable row of cards,
/// the „Szokásos utad” card above them, and the ride log beside.
struct MultiStopScreen: View {

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var favorites: FavoritesStore
    @ObservedObject private var watches = TransitWatchesStore.shared

    enum WatchView: String { case stops, rides }

    @AppStorage("mvk_watch_view") private var view: WatchView = .stops
    @State private var isPickerOpen = false
    @State private var isReordering = false
    @State private var page: String?
    /// A deep link has just chosen a card; the next "nearest stop changed"
    /// nudge must not immediately steal it back.
    @State private var holdsDeepLinkPage = false

    private static let quickStops: [(label: String, match: String, mode: TransitMode?)] = [
        ("Tiszai pályaudvar", "Tiszai", nil),
        ("Miskolc-Tiszai (vasút)", "Miskolc-Tiszai", .rail),
        ("Autóbusz-állomás (Volán)", "Miskolc, autóbusz-állomás", .coach),
        ("Búza tér", "Búza", nil),
        ("Villanyrendőr", "Villany", nil),
        ("Újgyőri főtér", "Újgyőri", nil),
        ("Avas kilátó", "Avas kilátó", nil),
        ("Miskolctapolca, Barlangfürdő", "Tapolca", nil),
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            HairlineDivider()
            switch view {
            case .rides:
                ScrollView {
                    RidesPanelHost()
                        .padding(12)
                }
            case .stops:
                stopsView
            }
        }
        .background(AppBackground())
        .sheet(isPresented: $isPickerOpen) {
            AddStopSheet(stops: store.stops)
                .presentationDetents([.large])
                .presentationBackground(Theme.background)
        }
        .onChange(of: nearestId) { _, id in
            guard id != nil, !isReordering else { return }
            guard !holdsDeepLinkPage else {
                holdsDeepLinkPage = false
                return
            }
            withAnimation(Theme.Motion.normalAnimation) { page = cardKeys.first }
        }
        .onChange(of: navigation.watchlistFocusStopId) { _, _ in applyDeepLinkFocus() }
        .onChange(of: watchedStops.map(\.id)) { _, _ in applyDeepLinkFocus() }
        .onAppear {
            AlertsStore.shared.refresh()
            applyDeepLinkFocus()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            viewSwitcher
            if view == .stops {
                if canNearest || canReorder || !kioskStopIds.isEmpty { moreMenu }
                addButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card.opacity(0.6))
    }

    private var viewSwitcher: some View {
        HStack(spacing: 4) {
            ForEach([(WatchView.stops, "Megállók", "dot.radiowaves.left.and.right"), (WatchView.rides, "Utazásaim", "ticket")], id: \.0) { item in
                let on = view == item.0
                Button {
                    withAnimation(Theme.Motion.fastAnimation) { view = item.0 }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.2).font(.system(size: 12, weight: .semibold))
                        Text(item.1).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(on ? Theme.foreground : Theme.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .fill(Theme.card)
                                .mvkShadow(Theme.Shadow.sm)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Figyelő nézet")
    }

    private var moreMenu: some View {
        Menu {
            if canNearest {
                Toggle(isOn: $favorites.nearestFirstEnabled) {
                    Label("Legközelebbi elöl", systemImage: "location.viewfinder")
                }
            }
            if canReorder {
                Button {
                    withAnimation(Theme.Motion.normalAnimation) { isReordering.toggle() }
                } label: {
                    Label(isReordering ? "Sorrend kész" : "Sorrend módosítása", systemImage: isReordering ? "checkmark" : "arrow.left.arrow.right")
                }
            }
            if !kioskStopIds.isEmpty {
                Button {
                    navigation.kioskStopIds = kioskStopIds
                } label: {
                    Label("Kijelző tévére", systemImage: "play.tv")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.foreground)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .accessibilityLabel("További lehetőségek")
    }

    private var addButton: some View {
        Button {
            isPickerOpen = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                if totalCount > 0 {
                    Text("\(totalCount)")
                        .font(Theme.mono(10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.primaryForeground.opacity(0.2), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .foregroundStyle(Theme.primaryForeground)
            .padding(.horizontal, 12)
            .frame(minWidth: 40, minHeight: 40)
            .glassEffect(.regular.tint(Theme.primary).interactive(), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Megálló felvétele")
    }

    // MARK: - Stops view

    @ViewBuilder
    private var stopsView: some View {
        if cardKeys.isEmpty {
            ScrollView {
                VStack(spacing: 16) {
                    CommuteCard()
                    if store.stops.isEmpty && !favorites.stopIds.isEmpty {
                        Text("Megállók betöltése…")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.vertical, 40)
                    } else {
                        emptyState
                    }
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 0) {
                CommuteCard()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                carousel
                    .padding(.top, 16)
            }
        }
    }

    private var carousel: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(watchedStops.enumerated()), id: \.element.id) { index, stop in
                            StopCardView(
                                stop: stop,
                                distanceKm: distances[stop.id],
                                isNearest: stop.id == nearestId,
                                reorder: isReordering ? StopCardReorder(
                                    onMoveEarlier: { move(stop.id, by: -1) },
                                    onMoveLater: { move(stop.id, by: 1) },
                                    canMoveEarlier: index > 0,
                                    canMoveLater: index < watchedStops.count - 1
                                ) : nil,
                                onRemove: { favorites.remove($0) },
                                onFocusMap: { stop, tripId, vehicleId in
                                    navigation.focusStopOnMap(stop, tripId: tripId, vehicleId: vehicleId)
                                }
                            )
                            .frame(width: max(0, proxy.size.width - 32))
                            .id(stop.id)
                        }
                        ForEach(shownRelations) { relation in
                            RelationCard(
                                relation: relation,
                                stops: store.stops,
                                onRemove: { watches.removeRelation(relation) },
                                onFocusTrip: focusTrip
                            )
                            .frame(width: max(0, proxy.size.width - 32))
                            .id("rel:\(relation.id)")
                        }
                        ForEach(shownTrains, id: \.self) { train in
                            TrainCard(
                                trainNo: train,
                                onRemove: { watches.toggleTrain(train) },
                                onFocusTrip: focusTrip
                            )
                            .frame(width: max(0, proxy.size.width - 32))
                            .id("train:\(train)")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .frame(height: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $page, anchor: .center)
            }

            if cardKeys.count > 1 { pager }
        }
    }

    private var pager: some View {
        let index = currentIndex
        return VStack(spacing: 0) {
            HairlineDivider()
            HStack(spacing: 12) {
                OutlineIconButton(systemName: "chevron.left", label: "Előző megálló", size: 40) { step(-1) }
                    .disabled(index <= 0)

                Group {
                    if cardKeys.count <= 8 {
                        HStack(spacing: 6) {
                            ForEach(Array(cardLabels.enumerated()), id: \.offset) { i, label in
                                Button {
                                    withAnimation(Theme.Motion.normalAnimation) { page = cardKeys[i] }
                                } label: {
                                    Capsule()
                                        .fill(i == index ? Theme.primary : Theme.mutedForeground.opacity(0.35))
                                        .frame(width: i == index ? 24 : 8, height: 8)
                                        .frame(height: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Ugrás ide: \(label)")
                                .accessibilityAddTraits(i == index ? .isSelected : [])
                            }
                        }
                        .animation(Theme.Motion.fastAnimation, value: index)
                    } else {
                        Text("\(index + 1) / \(cardKeys.count)")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .frame(maxWidth: .infinity)

                OutlineIconButton(systemName: "chevron.right", label: "Következő megálló", size: 40) { step(1) }
                    .disabled(index >= cardKeys.count - 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.card)
        }
    }

    private var currentIndex: Int {
        page.flatMap { cardKeys.firstIndex(of: $0) } ?? 0
    }

    private func step(_ delta: Int) {
        let target = min(cardKeys.count - 1, max(0, currentIndex + delta))
        withAnimation(Theme.Motion.normalAnimation) { page = cardKeys[target] }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 56, height: 56)
                .background(Theme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))

            Text("A figyelő üres")
                .font(.system(size: 18, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Theme.foreground)
                .padding(.top, 16)

            Button {
                isPickerOpen = true
            } label: {
                Label("Megállók böngészése", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.primary)
            .padding(.top, 20)

            HairlineDivider()
                .padding(.top, 32)

            Text("Gyakori csomópontok")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, 20)

            FlowLayout(spacing: 8, lineSpacing: 8, alignment: .center) {
                ForEach(Self.quickStops.filter { $0.mode.map(enabledModes.contains) ?? true }, id: \.match) { preset in
                    Button {
                        addByName(preset.match)
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                    .strokeBorder(Theme.input, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(maxWidth: 576)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .mvkShadow(Theme.Shadow.lg)
    }

    // MARK: - Deep links

    /// Scrolls to the card a `mvkpp://watch/<stop>` link asked for.
    private func applyDeepLinkFocus() {
        guard let stopId = navigation.watchlistFocusStopId,
              watchedStops.contains(where: { $0.id == stopId })
        else { return }
        view = .stops
        holdsDeepLinkPage = true
        withAnimation(Theme.Motion.normalAnimation) { page = stopId }
        navigation.watchlistFocusStopId = nil
    }

    private func focusTrip(_ tripId: String, _ vehicleId: String?) {
        navigation.tab = .map
        navigation.focusTrip(tripId, vehicleId: vehicleId)
    }

    // MARK: - Derived data

    private var enabledModes: [TransitMode] { TransitMode.enabled() }

    private func feedOn(_ id: String) -> Bool {
        switch TransitFeed.of(id: id) {
        case .mvk: return true
        case .coach: return enabledModes.contains(.coach)
        case .rail: return enabledModes.contains(.rail)
        }
    }

    private var shownRelations: [RelationWatch] {
        watches.relations.filter { feedOn($0.from) && feedOn($0.to) }
    }

    private var shownTrains: [String] {
        enabledModes.contains(.rail) ? watches.trains : []
    }

    private var manualOrder: [Stop] {
        favorites.stopIds.compactMap { store.stop(id: $0) }
    }

    private var distances: [String: Double] {
        guard let position = location.position else { return [:] }
        return manualOrder.reduce(into: [:]) { result, stop in
            result[stop.id] = Geo.distanceKm(position.lat, position.lon, stop.lat, stop.lon)
        }
    }

    private var sortsByDistance: Bool {
        favorites.nearestFirstEnabled && !isReordering && !distances.isEmpty
    }

    private var watchedStops: [Stop] {
        guard sortsByDistance else { return manualOrder }
        return manualOrder.sorted { (distances[$0.id] ?? .infinity) < (distances[$1.id] ?? .infinity) }
    }

    private var nearestId: String? {
        sortsByDistance ? watchedStops.first?.id : nil
    }

    private var cardKeys: [String] {
        watchedStops.map(\.id) + shownRelations.map { "rel:\($0.id)" } + shownTrains.map { "train:\($0)" }
    }

    private var cardLabels: [String] {
        let name = { (id: String) in store.stop(id: id)?.name ?? id }
        return watchedStops.map(\.name)
            + shownRelations.map { "\(name($0.from)) → \(name($0.to))" }
            + shownTrains.map { "\(HungarianText.withSuffix($0)) vonat" }
    }

    private var totalCount: Int {
        favorites.stopIds.filter(feedOn).count + shownRelations.count + shownTrains.count
    }

    private var canNearest: Bool { manualOrder.count > 1 && location.position != nil }
    private var canReorder: Bool { watchedStops.count > 1 && !sortsByDistance }

    /// The passenger-information display for a TV or tablet (up to 3 stops).
    private var kioskStopIds: [String] { watchedStops.prefix(3).map(\.id) }

    private func move(_ stopId: String, by delta: Int) {
        guard let from = favorites.stopIds.firstIndex(of: stopId) else { return }
        let to = from + delta
        guard to >= 0, to < favorites.stopIds.count else { return }
        withAnimation(Theme.Motion.normalAnimation) {
            favorites.move(from: IndexSet(integer: from), to: delta > 0 ? to + 1 : to)
        }
    }

    private func addByName(_ needle: String) {
        let query = needle.normalizedForSearch
        guard let found = store.stops.first(where: {
            $0.name.normalizedForSearch.contains(query) || $0.id.lowercased().contains(query)
        }) else { return }
        favorites.toggle(found.id)
    }
}
