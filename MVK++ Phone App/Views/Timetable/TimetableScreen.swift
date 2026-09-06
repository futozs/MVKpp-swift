//
//  TimetableScreen.swift
//  MVK++ Phone App
//

import SwiftUI

/// Route list for a chosen day. The web app puts this in a permanent sidebar;
/// on a phone it is the first level of a navigation stack.
struct TimetableScreen: View {

    @EnvironmentObject private var store: TransitStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var lineFavorites: LineFavoritesStore

    @StateObject private var model = TimetableModel()
    @State private var query = ""
    @State private var isDatePickerOpen = false

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.routesError {
                    ScrollView { ErrorNotice(message: error).padding(16) }
                } else if model.isLoadingRoutes && model.routes.isEmpty {
                    ProgressView("Járatok betöltése…")
                        .font(Theme.mono(12, weight: .regular))
                        .tint(Theme.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    routeList
                }
            }
            .background(AppBackground())
            .navigationTitle("Menetrend")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Járat vagy végállomás")
            .safeAreaInset(edge: .top) { dayBar }
            .task { await model.start() }
            .onDisappear { model.stop() }
        }
    }

    // MARK: - Day bar

    private var dayBar: some View {
        HStack(spacing: 12) {
            stepButton(systemImage: "chevron.left", days: -1)
                .disabled(minIso.map { model.date <= $0 } ?? false)

            Button {
                isDatePickerOpen = true
            } label: {
                VStack(spacing: 1) {
                    Text(model.dateLabel)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                    Text("\(model.weekdayLabel) · \(model.routes.count) járat")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            stepButton(systemImage: "chevron.right", days: 1)
                .disabled(maxIso.map { model.date >= $0 } ?? false)
        }
        .overlay(alignment: .trailing) {
            // Only earns its place once you have wandered off today.
            if !model.isToday {
                Button("Ma") { model.goToToday() }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(Theme.primary)
                    .offset(y: 34)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.normalAnimation, value: model.isToday)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, model.isToday ? 8 : 30)
        .background(.bar)
        .sheet(isPresented: $isDatePickerOpen) {
            NavigationStack {
                DatePicker(
                    "Menetrend napja",
                    selection: dateBinding,
                    in: dateRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(Theme.primary)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(AppBackground())
                .navigationTitle("Nap választása")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kész") { isDatePickerOpen = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func stepButton(systemImage: String, days: Int) -> some View {
        Button {
            model.shiftDate(by: days, min: minIso, max: maxIso)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .accessibilityLabel(days < 0 ? "Előző nap" : "Következő nap")
    }

    // MARK: - Route list

    private var routeList: some View {
        List {
            if !favoriteLines.isEmpty && query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    ForEach(favoriteLines, id: \.id) { favorite in
                        NavigationLink {
                            RouteTimetableView(
                                route: favorite.route,
                                initialDir: favorite.dir,
                                model: model
                            )
                        } label: {
                            routeRow(
                                favorite.route,
                                subtitle: favorite.headsign.isEmpty ? favorite.route.long : favorite.headsign,
                                tripsToday: favorite.tripsToday
                            )
                        }
                        .listRowBackground(Theme.primary.opacity(0.07))
                    }
                } header: {
                    Label("Kedvencek", systemImage: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }

            Section {
                ForEach(visibleRoutes) { route in
                    NavigationLink {
                        RouteTimetableView(route: route, initialDir: nil, model: model)
                    } label: {
                        routeRow(
                            route,
                            subtitle: route.long,
                            tripsToday: route.directions.reduce(0) { $0 + $1.tripsToday },
                            cancelledCount: model.cancelledCountByRoute[route.id] ?? 0
                        )
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .mvkBackground()
        .overlay {
            if visibleRoutes.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func routeRow(
        _ route: TimetableRoute,
        subtitle: String,
        tripsToday: Int,
        cancelledCount: Int = 0
    ) -> some View {
        HStack(spacing: 10) {
            RouteTile(short: route.short, colorHex: route.color, textHex: route.text)

            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Text(serviceLabel(tripsToday))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mutedForeground)
            }

            Spacer(minLength: 4)

            if cancelledCount > 0 {
                Label("\(cancelledCount)", systemImage: "nosign")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.destructive)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Theme.destructive.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .accessibilityLabel("\(cancelledCount) kihúzott menet ezen a járaton")
            }
        }
        // A route with no service today stays listed but recedes — its
        // absence is information the rider needs.
        .opacity(tripsToday == 0 ? 0.55 : 1)
    }

    private func serviceLabel(_ tripsToday: Int) -> String {
        if tripsToday > 0 {
            return model.isToday ? "\(tripsToday) menet ma" : "\(tripsToday) menet ezen a napon"
        }
        return model.isToday ? "Ma nem közlekedik" : "Ezen a napon nem közlekedik"
    }

    // MARK: - Derived data

    private var visibleRoutes: [TimetableRoute] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return model.routes }
        return model.routes.filter { route in
            route.short.containsNormalized(needle)
                || route.long.containsNormalized(needle)
                || route.directions.contains { $0.headsign.containsNormalized(needle) }
        }
    }

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
            return FavoriteEntry(
                route: route,
                dir: direction.dir,
                headsign: direction.headsign,
                tripsToday: direction.tripsToday
            )
        }
    }

    // MARK: - Date bounds
    //
    // The picker is limited to what the gateway can actually answer: the live
    // service window plus however far back the archive reaches.

    private var minIso: String? {
        [store.gtfsMeta?.serviceRange?.from, store.gtfsMeta?.archiveRange?.from]
            .compactMap { $0 }
            .compactMap(TimetableModel.ymdToIso)
            .min()
    }

    private var maxIso: String? {
        [store.gtfsMeta?.serviceRange?.to, store.gtfsMeta?.archiveRange?.to]
            .compactMap { $0 }
            .compactMap(TimetableModel.ymdToIso)
            .max()
    }

    private var dateRange: ClosedRange<Date> {
        let lower = minIso.flatMap(TimetableModel.parse)
            ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let upper = maxIso.flatMap(TimetableModel.parse)
            ?? Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        return lower <= upper ? lower...upper : upper...lower
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { TimetableModel.parse(model.date) ?? Date() },
            set: { newValue in
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                model.date = formatter.string(from: newValue)
            }
        )
    }
}
