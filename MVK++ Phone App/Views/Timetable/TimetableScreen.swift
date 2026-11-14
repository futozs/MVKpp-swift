//
//  TimetableScreen.swift
//  MVK++ Phone App
//

import SwiftUI

/// The route list for a chosen service day. On the web this is the sidebar;
/// on a phone it is the first level, and a chosen route opens over it.
struct TimetableScreen: View {

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var lineFavorites: LineFavoritesStore

    @StateObject private var model = TimetableModel()
    @State private var query = ""
    @State private var disruptionsOpen = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Rectangle().fill(Theme.border).frame(height: 1)
                list
            }
            .background(Theme.card.ignoresSafeArea())
            .navigationTitle("Menetrend")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: routeOpen) {
                RouteTimetableView(model: model)
            }
            .sheet(isPresented: $disruptionsOpen) {
                DisruptionsSheet()
            }
            .task {
                model.setRange(minIso: minIso, maxIso: maxIso)
                model.start()
            }
            .onChange(of: rangeKey) { _, _ in model.setRange(minIso: minIso, maxIso: maxIso) }
            .onDisappear { model.stop() }
        }
    }

    private var routeOpen: Binding<Bool> {
        Binding(
            get: { model.selectedRoute != nil },
            set: { open in if !open { model.closeRoute() } }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField

            if model.groups.count > 2 {
                groupPicker.padding(.top, 8)
            }

            HStack(spacing: 8) {
                TimetableDayPicker(
                    value: model.date,
                    minIso: model.minIso,
                    maxIso: model.maxIso,
                    todayIso: TimetableModel.todayIso(),
                    onShift: model.shiftDate(by:),
                    onPick: model.setDate
                )
                .frame(minWidth: 176, maxWidth: .infinity)
                .layoutPriority(1)
                disruptionsButton
            }
            .padding(.top, 8)

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Text("\(visibleRoutes.count) járat · \(model.weekdayLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                    if model.isOffline { OfflineTag(compact: true) }
                }
                Spacer(minLength: 0)
                HereChip(stops: store.stops)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.mutedForeground)
            TextField("", text: $query, prompt: Text("Járat vagy végállomás").foregroundStyle(Theme.mutedForeground))
                .font(.system(size: 14))
                .foregroundStyle(Theme.foreground)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Járat keresése")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keresés törlése")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(searchFocused ? Theme.ring : Theme.input, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    private var groupPicker: some View {
        HStack(spacing: 4) {
            ForEach(model.groups) { group in
                let isOn = model.activeGroup == group
                Button {
                    withAnimation(Theme.Motion.fastAnimation) { model.group = group }
                } label: {
                    Text(group.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOn ? Theme.primaryForeground : Theme.mutedForeground)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(isOn ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .mvkShadow(isOn ? Theme.Shadow.sm : Theme.Shadow.Level(radius: 0, y: 0, opacity: 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Melyik járatok")
    }

    private var disruptionsButton: some View {
        let count = model.todayCancelledCount
        return Button {
            disruptionsOpen = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "nosign")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(count > 0 ? Theme.destructive : Theme.mutedForeground)
                Text("Mai zavarok")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(count > 0 ? Theme.foreground : Theme.mutedForeground)
                    .lineLimit(1)
                    .fixedSize()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.destructive)
                        .padding(.horizontal, 6)
                        .background(Theme.destructive.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(count > 0 ? Theme.destructive.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(count > 0 ? Theme.destructive.opacity(0.4) : Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TimetablePressStyle())
        .accessibilityHint("Mai zavarok: mi marad ki, mi jön helyette")
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        let routes = visibleRoutes
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        ScrollView {
            if let error = model.routesError {
                ErrorNotice(message: error)
                    .padding(12)
            } else if routes.isEmpty {
                Text(trimmed.isEmpty
                     ? (model.routes.isEmpty ? "Járatok betöltése…" : "Ezen a napon nem közlekedik járat.")
                     : "Nincs „\(trimmed)” jelzésű járat.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 32)
            } else {
                LazyVStack(spacing: 0) {
                    if !favoriteLines.isEmpty && trimmed.isEmpty {
                        favoritesSection
                    }
                    ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                        if let header = groupHeader(at: index, in: routes) {
                            Text(header.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(Theme.mutedForeground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.muted.opacity(0.4))
                        }
                        routeRow(route)
                        if index < routes.count - 1 {
                            Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func groupHeader(at index: Int, in routes: [TimetableRoute]) -> String? {
        guard model.activeGroup == .all, model.groups.count > 2 else { return nil }
        let group = TimetableGroup.of(routes[index])
        guard index == 0 || TimetableGroup.of(routes[index - 1]) != group else { return nil }
        return group.title
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.primary)
                Text("KEDVENCEK")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ForEach(favoriteLines, id: \.id) { favorite in
                let isActive = favorite.route.id == model.selectedRouteId && favorite.dir == model.selectedDir
                Button {
                    model.open(routeId: favorite.route.id, dir: favorite.dir)
                } label: {
                    rowContent(
                        favorite.route,
                        title: favorite.headsign.isEmpty ? favorite.route.long : favorite.headsign,
                        subtitle: serviceLabel(favorite.tripsToday),
                        cancelledCount: 0
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isActive ? Theme.primary.opacity(0.10) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TimetablePressStyle(cornerRadius: 0))
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
        .background(Theme.muted.opacity(0.25))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func routeRow(_ route: TimetableRoute) -> some View {
        let isActive = route.id == model.selectedRouteId
        let tripsToday = route.directions.reduce(0) { $0 + $1.tripsToday }
        let operatorPrefix = route.mode == .coach && route.operator != nil && route.operator != "Helyközi busz"
            ? "\(route.operator ?? "") · " : ""
        return Button {
            model.selectRoute(route)
        } label: {
            rowContent(
                route,
                title: route.long,
                subtitle: operatorPrefix + serviceLabel(tripsToday),
                cancelledCount: model.cancelledCountByRoute[route.id] ?? 0
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isActive ? Theme.primary.opacity(0.10) : .clear)
            .opacity(tripsToday == 0 && !isActive ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(TimetablePressStyle(cornerRadius: 0))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func rowContent(_ route: TimetableRoute, title: String, subtitle: String, cancelledCount: Int) -> some View {
        HStack(spacing: 10) {
            RouteTile(short: route.short, colorHex: route.color, textHex: route.text)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if cancelledCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "nosign").font(.system(size: 8, weight: .bold))
                    Text("\(cancelledCount)").font(Theme.mono(10))
                }
                .foregroundStyle(Theme.destructive)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.destructive.opacity(0.4), lineWidth: 1))
                .accessibilityLabel("\(cancelledCount) kihúzott menet \(model.isToday ? "ma" : "ezen a napon") ezen a járaton")
            }
        }
    }

    private func serviceLabel(_ tripsToday: Int) -> String {
        if tripsToday > 0 {
            return "\(tripsToday) \(model.isToday ? "menet ma" : "menet ezen a napon")"
        }
        return model.isToday ? "Ma nem közlekedik" : "Ezen a napon nem közlekedik"
    }

    // MARK: - Derived

    private var visibleRoutes: [TimetableRoute] { model.visibleRoutes(query: query) }

    private struct FavoriteEntry {
        let route: TimetableRoute
        let dir: String
        let headsign: String
        let tripsToday: Int
        var id: String { "\(route.id)|\(dir)" }
    }

    private var favoriteLines: [FavoriteEntry] {
        lineFavorites.lines.compactMap { favorite in
            guard let route = model.routes.first(where: { $0.id == favorite.routeId }),
                  let direction = route.directions.first(where: { $0.dir == favorite.dir })
            else { return nil }
            return FavoriteEntry(route: route, dir: direction.dir, headsign: direction.headsign, tripsToday: direction.tripsToday)
        }
    }

    // MARK: - Date bounds
    //
    // The picker only offers what the gateway can answer: the live service
    // window plus however far back the archive reaches.

    private var minIso: String? {
        [store.gtfsMeta?.serviceRange?.from, store.gtfsMeta?.archiveRange?.from]
            .compactMap { $0 }
            .compactMap(ServiceClock.ymdToIso)
            .min()
    }

    private var maxIso: String? {
        [store.gtfsMeta?.serviceRange?.to, store.gtfsMeta?.archiveRange?.to]
            .compactMap { $0 }
            .compactMap(ServiceClock.ymdToIso)
            .max()
    }

    private var rangeKey: String { "\(minIso ?? "")|\(maxIso ?? "")" }
}
