//
//  TimetableViews.swift
//  MVK++ Watch App
//

import SwiftUI

/// Menetrend: a route, then its direction, then a stop, then the day's
/// departures from there. The rider's saved lines (synced from the phone)
/// sit on top and skip straight to the stops.
struct TimetableRoutesView: View {
    @EnvironmentObject private var router: WatchRouter
    @EnvironmentObject private var link: WatchLink
    @State private var routes: [TimetableRoute] = []
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !favorites.isEmpty {
                    Text("Kedvenc vonalaid")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.mutedForeground)
                    ForEach(favorites, id: \.line.id) { item in
                        Button {
                            router.push(.timetableStops(routeId: item.route.id, dir: item.line.dir))
                        } label: {
                            HStack(spacing: 7) {
                                RouteTile(short: item.route.short, colorHex: item.route.color, textHex: item.route.text, size: .medium)
                                Text(item.route.directions.first { $0.dir == item.line.dir }?.headsign ?? item.route.long)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                if routes.isEmpty {
                    if let error {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(Theme.late)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("Minden vonal")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.mutedForeground)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(routes) { route in
                            Button {
                                router.push(.timetableRoute(route))
                            } label: {
                                RouteTile(short: route.short, colorHex: route.color, textHex: route.text, size: .medium)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(route.short). vonal")
                        }
                    }
                }
            }
        }
        .navigationTitle("Menetrend")
        .task {
            guard routes.isEmpty else { return }
            do {
                routes = try await APIClient.shared.timetableRoutes().routes
            } catch {
                self.error = "A vonalak nem érhetők el."
            }
        }
    }

    private struct FavoriteRoute {
        let line: FavoriteLine
        let route: TimetableRoute
    }

    private var favorites: [FavoriteRoute] {
        let index = Dictionary(routes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return link.settings.lineFavorites.compactMap { line in
            index[line.routeId].map { FavoriteRoute(line: line, route: $0) }
        }
    }
}

struct TimetableDirectionsView: View {
    let route: TimetableRoute
    @EnvironmentObject private var router: WatchRouter

    var body: some View {
        List {
            Section {
                Text(route.long)
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedForeground)
                    .listRowBackground(Color.clear)
            }
            ForEach(route.directions) { direction in
                Button {
                    router.push(.timetableStops(routeId: route.id, dir: direction.dir))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(direction.headsign)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                        Text(direction.tripsToday > 0 ? "ma \(direction.tripsToday) indulás" : "ma nem közlekedik")
                            .font(.caption2)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
        }
        .navigationTitle(route.short)
    }
}

/// One direction of a route: its stops, then a stop's times.
struct TimetableStopsView: View {
    let routeId: String
    let dir: String
    @State private var timetable: TimetableResponse?
    @State private var error: String?

    var body: some View {
        List {
            if let timetable {
                Section {
                    ForEach(Array(timetable.stops.enumerated()), id: \.offset) { index, stop in
                        NavigationLink {
                            TimetableStopTimesView(timetable: timetable, stopIndex: index)
                        } label: {
                            HStack(spacing: 6) {
                                Text(stop.name)
                                    .font(.footnote)
                                    .lineLimit(2)
                                Spacer(minLength: 2)
                                if let next = nextTime(at: index, in: timetable) {
                                    Text(next)
                                        .font(Theme.mono(11, weight: .bold))
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(timetable.headsign)
                        .lineLimit(2)
                }
                if let note = timetable.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Theme.mutedForeground)
                }
            } else if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.late)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(timetable?.route.short ?? "Menetrend")
        .task(id: "\(routeId)|\(dir)") {
            do {
                timetable = try await APIClient.shared.timetable(routeId: routeId, dir: dir)
            } catch {
                self.error = "A menetrend nem érhető el."
            }
        }
    }

    private func nextTime(at index: Int, in timetable: TimetableResponse) -> String? {
        let now = TimetableClock.nowMinutes()
        return timetable.trips
            .compactMap { trip in trip.times.indices.contains(index) ? trip.times[index] : nil }
            .first { TimetableClock.minutes($0) >= now }
    }
}

/// Every departure from one stop today, scrolled to the next one; the
/// ones gone are dimmed.
struct TimetableStopTimesView: View {
    let timetable: TimetableResponse
    let stopIndex: Int

    var body: some View {
        let times = timetable.trips.compactMap { trip -> (id: String, time: String)? in
            guard trip.times.indices.contains(stopIndex), let time = trip.times[stopIndex] else { return nil }
            return (trip.tripId, time)
        }
        let now = TimetableClock.nowMinutes()
        let nextId = times.first { TimetableClock.minutes($0.time) >= now }?.id

        ScrollViewReader { proxy in
            List {
                if times.isEmpty {
                    Text("Innen ma nem indul járat.")
                        .font(.footnote)
                        .foregroundStyle(Theme.mutedForeground)
                }
                ForEach(times, id: \.id) { item in
                    let gone = TimetableClock.minutes(item.time) < now
                    HStack {
                        Text(item.time)
                            .font(Theme.mono(16, weight: item.id == nextId ? .heavy : .semibold))
                            .foregroundStyle(item.id == nextId ? Theme.primary : Theme.foreground)
                        Spacer()
                        if item.id == nextId {
                            Text(TimetableClock.until(item.time, from: now))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                        }
                    }
                    .opacity(gone ? 0.4 : 1)
                    .id(item.id)
                }
            }
            .onAppear {
                if let nextId { proxy.scrollTo(nextId, anchor: .top) }
            }
        }
        .navigationTitle(timetable.stops.indices.contains(stopIndex) ? timetable.stops[stopIndex].name : "Indulások")
    }
}

/// Timetable "HH:mm" strings run past 24:00 for the night's last trips and
/// count from the service day's start (03:00 rolls the day over).
enum TimetableClock {
    static func minutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    static func nowMinutes(_ date: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes < 3 * 60 ? minutes + 24 * 60 : minutes
    }

    static func until(_ time: String, from now: Int) -> String {
        let delta = minutes(time) - now
        return delta <= 0 ? "most" : "\(Countdown.compact(minutes: delta)) múlva"
    }
}
