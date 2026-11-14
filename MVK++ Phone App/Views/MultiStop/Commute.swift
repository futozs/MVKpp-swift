//
//  Commute.swift
//  MVK++ Phone App
//

import Combine
import Foundation

/// The fields of a logged ride that commute detection needs, read straight
/// from the web shape of the ride log.
struct CommuteRide: Decodable {
    let route: String
    let headsign: String
    let color: String?
    let text: String?
    let fromStopId: String?
    let fromStopName: String?
    let toStopName: String?
    let boardedAt: Double
    let serviceDate: String
    let chainId: String?
}

/// A regular trip learnt from the ride log: the same line, from the same stop,
/// at about the same time, on at least three separate days in six weeks.
/// A port of the core `commute`.
struct Commute: Equatable {
    enum DayKind: String { case workday, weekend }

    let key: String
    let route: String
    let headsign: String
    let color: String
    let text: String
    let fromStopId: String
    let fromStopName: String
    let toStopName: String?
    let dayKind: DayKind
    /// Usual boarding time, Budapest minute of the day.
    let minute: Int
    let spreadMin: Int
    let rides: Int
    let days: Int
    let lastAt: Double
    /// ISO weekdays it happened on (1 = Monday).
    let dows: [Int]
    /// Every such day, not just some.
    let daily: Bool
    /// Stayed on at the terminus for the next run.
    let loop: Bool

    static let lookbackDays = 42.0
    static let minRides = 3
    static let minDays = 3
    static let gapMin = 12
    static let dailyWorkdays = 4
    static let showBeforeMin = 90
    static let showAfterMin = 15

    private static let dowAdverb = ["", "hétfőnként", "keddenként", "szerdánként", "csütörtökönként", "péntekenként", "szombatonként", "vasárnaponként"]

    /// „minden munkanap” or „szerdánként és csütörtökönként”.
    var daysText: String {
        if daily { return dayKind == .workday ? "minden munkanap" : "hétvégente" }
        let names = dows.map { Self.dowAdverb[$0] }
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return "\(names.dropLast().joined(separator: ", ")) és \(last)"
    }

    static func detect(_ rides: [CommuteRide], now: Double) -> [Commute] {
        let since = now - lookbackDays * 86_400
        var groups: [String: [(ride: CommuteRide, minute: Int, loop: Bool)]] = [:]
        var order: [String] = []
        for (ride, loop) in mergeChains(rides) {
            guard let from = ride.fromStopId, ride.boardedAt >= since, ride.boardedAt <= now else { continue }
            let key = "\(ride.route)|\(from)|\(HungarianCalendar.dayKind(ride.serviceDate).rawValue)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append((ride, BudapestClock.minute(ride.boardedAt), loop))
        }

        var out: [Commute] = []
        for key in order {
            let list = (groups[key] ?? []).sorted { $0.minute < $1.minute }
            var cluster: [(ride: CommuteRide, minute: Int, loop: Bool)] = []
            func flush() {
                defer { cluster = [] }
                let days = Set(cluster.map(\.ride.serviceDate)).count
                guard cluster.count >= minRides, days >= minDays,
                      let latest = cluster.max(by: { $0.ride.boardedAt < $1.ride.boardedAt }),
                      let from = latest.ride.fromStopId else { return }
                let mins = cluster.map(\.minute)
                let median = mins[mins.count / 2]
                let dows = Array(Set(cluster.map { BudapestClock.isoDow($0.ride.serviceDate) })).sorted()
                let kind = HungarianCalendar.dayKind(latest.ride.serviceDate)
                out.append(Commute(
                    key: "\(key)|\(median)",
                    route: latest.ride.route,
                    headsign: mostCommon(cluster.map(\.ride.headsign)) ?? latest.ride.headsign,
                    color: latest.ride.color ?? "1FB574",
                    text: latest.ride.text ?? "FFFFFF",
                    fromStopId: from,
                    fromStopName: latest.ride.fromStopName ?? from,
                    toStopName: mostCommon(cluster.map(\.ride.toStopName)) ?? nil,
                    dayKind: kind,
                    minute: median,
                    spreadMin: (mins.last ?? 0) - (mins.first ?? 0),
                    rides: cluster.count,
                    days: days,
                    lastAt: latest.ride.boardedAt,
                    dows: dows,
                    daily: kind == .workday ? dows.count >= dailyWorkdays : dows.count >= 2,
                    loop: cluster.filter(\.loop).count * 2 >= cluster.count
                ))
            }
            for entry in list {
                if let last = cluster.last, entry.minute - last.minute > gapMin { flush() }
                cluster.append(entry)
            }
            flush()
        }
        return out.sorted { $0.rides != $1.rides ? $0.rides > $1.rides : $0.lastAt > $1.lastAt }
    }

    /// The commute relevant now: usual today, at most 90 minutes ahead or 15
    /// past its time — the closest one.
    static func upcoming(_ commutes: [Commute], now: Double) -> Commute? {
        let today = BudapestClock.serviceIso(now)
        let nowMin = BudapestClock.minute(now)
        var best: Commute?
        var bestDistance = Int.max
        for commute in commutes where commute.isUsual(on: today) {
            let d = ((commute.minute - nowMin + 2160) % 1440) - 720
            guard d <= showBeforeMin, d >= -showAfterMin else { continue }
            if abs(d) < bestDistance {
                best = commute
                bestDistance = abs(d)
            }
        }
        return best
    }

    func isUsual(on iso: String) -> Bool {
        dayKind == HungarianCalendar.dayKind(iso) && (daily || dows.contains(BudapestClock.isoDow(iso)))
    }

    /// A loop trip's legs count as one: first boarding, last alighting.
    private static func mergeChains(_ rides: [CommuteRide]) -> [(CommuteRide, Bool)] {
        var out: [(CommuteRide, Bool)] = []
        var chains: [String: [CommuteRide]] = [:]
        var chainOrder: [String] = []
        for ride in rides {
            guard let chain = ride.chainId else {
                out.append((ride, false))
                continue
            }
            if chains[chain] == nil { chainOrder.append(chain) }
            chains[chain, default: []].append(ride)
        }
        for chain in chainOrder {
            let legs = (chains[chain] ?? []).sorted { $0.boardedAt < $1.boardedAt }
            guard let first = legs.first, let last = legs.last else { continue }
            let merged = CommuteRide(
                route: first.route, headsign: first.headsign, color: first.color, text: first.text,
                fromStopId: first.fromStopId, fromStopName: first.fromStopName, toStopName: last.toStopName,
                boardedAt: first.boardedAt, serviceDate: first.serviceDate, chainId: first.chainId
            )
            out.append((merged, legs.count > 1))
        }
        return out
    }

    private static func mostCommon<T: Hashable>(_ values: [T]) -> T? {
        var counts: [T: Int] = [:]
        var order: [T] = []
        for value in values {
            if counts[value] == nil { order.append(value) }
            counts[value, default: 0] += 1
        }
        return order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }
}

/// Hungarian public holidays, for telling a workday from a weekend-like day.
enum HungarianCalendar {
    static func dayKind(_ iso: String) -> Commute.DayKind {
        isHoliday(iso) || BudapestClock.isoDow(iso) >= 6 ? .weekend : .workday
    }

    static func isHoliday(_ iso: String) -> Bool {
        guard let year = Int(iso.prefix(4)) else { return false }
        let fixed = ["01-01", "03-15", "05-01", "08-20", "10-23", "11-01", "12-24", "12-25", "12-26"]
        if fixed.contains(String(iso.suffix(5))) { return true }
        let easter = easterSunday(year)
        return [-2, 0, 1, 49, 50].contains { shift(easter, by: $0) == iso }
    }

    private static func easterSunday(_ year: Int) -> String {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func shift(_ iso: String, by days: Int) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              let moved = calendar.date(byAdding: .day, value: days, to: date)
        else { return iso }
        let out = calendar.dateComponents([.year, .month, .day], from: moved)
        return String(format: "%04d-%02d-%02d", out.year ?? 0, out.month ?? 0, out.day ?? 0)
    }
}

/// The ride log as the web stores it (`mvk_rides`), read for commute
/// detection. Reloads whenever the defaults change, so a ride finished or a
/// cloud sync lands on the card at once.
@MainActor
final class CommuteRideLog: ObservableObject {
    static let shared = CommuteRideLog()
    static let storageKey = "mvk_rides"

    @Published private(set) var rides: [CommuteRide] = []
    private var observer: AnyCancellable?
    private var lastData: Data?

    private init() {
        reload()
        observer = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    private func reload() {
        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: Self.storageKey) ?? defaults.string(forKey: Self.storageKey).map { Data($0.utf8) }
        guard data != lastData else { return }
        lastData = data
        rides = data.flatMap { try? JSONDecoder().decode([LossyRide].self, from: $0) }?.compactMap(\.ride) ?? []
    }

    /// One bad entry must not hide the whole log.
    private struct LossyRide: Decodable {
        let ride: CommuteRide?
        init(from decoder: Decoder) throws {
            ride = try? CommuteRide(from: decoder)
        }
    }
}
