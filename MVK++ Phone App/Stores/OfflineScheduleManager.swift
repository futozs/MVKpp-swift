//
//  OfflineScheduleManager.swift
//  MVK++ Phone App
//

import Combine
import Foundation
import WidgetKit

/// How much of the timetable to keep on the device.
///
/// The whole feed is only a couple of megabytes, so the choice is really about
/// how long the rider is willing to wait the first time — a day is seconds, the
/// full validity is about a minute.
enum OfflineScheduleScope: String, Identifiable, CaseIterable {
    case today
    case week
    case full

    var id: String { rawValue }

    var name: String {
        switch self {
        case .today: return "Mai nap"
        case .week: return "Egy hét"
        case .full: return "Teljes"
        }
    }

    /// The service days to pull, starting today and never reaching past the
    /// feed's own validity — the gateway has nothing to say beyond it.
    func days(from today: String, serviceRange: DateRange?) -> [String] {
        let last = serviceRange?.to
        let planned: [String]
        switch self {
        case .today: planned = [today]
        case .week: planned = ServiceDay.range(from: today, days: 7)
        case .full:
            guard let last, last >= today else { return [today] }
            planned = ServiceDay.range(from: today, to: last, limit: 31)
        }
        guard let last else { return planned }
        let trimmed = planned.filter { $0 <= last }
        return trimmed.isEmpty ? [today] : trimmed
    }
}

/// Why a day could not be stored. Distinct from `APIError` because "the
/// gateway answered, and the answer was an empty day" is not a server fault —
/// it is a date outside the feed's validity.
enum OfflineScheduleError: LocalizedError {
    case emptyDay

    var errorDescription: String? {
        switch self {
        case .emptyDay: return "Erre a napra nincs menetrend."
        }
    }
}

/// Downloads the timetable for offline use and keeps track of what is stored.
///
/// The point is a rider standing in the Avas underpass, or on the 68 out past
/// Bükkszentkereszt where there is no signal at all: the departure boards, the
/// timetable screen and the stop-code lookup all keep working, from the
/// schedule, with no network at any point.
@MainActor
final class OfflineScheduleManager: ObservableObject {

    static let shared = OfflineScheduleManager()

    struct Progress: Equatable {
        var dayNumber: Int
        var dayCount: Int
        var completed: Int
        var total: Int

        var fraction: Double {
            guard dayCount > 0 else { return 0 }
            let withinDay = total > 0 ? Double(completed) / Double(total) : 0
            return (Double(dayNumber - 1) + withinDay) / Double(dayCount)
        }
    }

    @Published private(set) var manifest: OfflineScheduleManifest = OfflineScheduleStore.manifest
    @Published private(set) var progress: Progress?
    @Published private(set) var bytes: Int64 = 0
    @Published var errorMessage: String?

    @Published var scope: OfflineScheduleScope {
        didSet { defaults.set(scope.rawValue, forKey: Self.scopeKey) }
    }

    /// On by default: the app is expected to have the timetable after the
    /// first launch without anyone being told to go and fetch it.
    @Published var autoDownloadEnabled: Bool {
        didSet { defaults.set(autoDownloadEnabled, forKey: Self.autoKey) }
    }

    private static let scopeKey = "mvk_offline_schedule_scope"
    private static let autoKey = "mvk_offline_schedule_auto"

    /// How polite to be with the gateway. Six is what saturates a phone
    /// connection here; the whole day is 114 small requests either way.
    private static let parallelism = 6

    private let defaults = UserDefaults(suiteName: FavoritesStore.appGroupID) ?? .standard
    private var downloadTask: Task<Void, Never>?

    private init() {
        // Full and automatic by default — a rider should not have to visit
        // Settings before the app works underground.
        scope = OfflineScheduleScope(rawValue: defaults.string(forKey: Self.scopeKey) ?? "") ?? .full
        autoDownloadEnabled = defaults.object(forKey: Self.autoKey) as? Bool ?? true
    }

    var isDownloading: Bool { progress != nil }

    /// True when what is stored still matches the feed the gateway serves.
    func isCurrent(feedVersion: String?) -> Bool {
        OfflineScheduleStore.isUsable(feedVersion: feedVersion)
    }

    /// Does the pack answer for today at all — the one thing the rest of the
    /// app cares about.
    var coversToday: Bool { manifest.covers(ServiceDay.ymd()) }

    // MARK: - Automatic refresh

    /// Called on launch. Downloads only when there is a real reason to: nothing
    /// stored, a new GTFS release, or a pack that has run past its last day.
    func refreshIfNeeded(meta: GtfsMeta?) async {
        guard autoDownloadEnabled, !isDownloading else { return }

        let today = ServiceDay.ymd()
        let stored = manifest
        let feedChanged = !stored.feedVersion.isEmpty
            && !(meta?.feedVersion ?? "").isEmpty
            && stored.feedVersion != meta?.feedVersion

        let needsDownload = stored.isEmpty || feedChanged || !stored.covers(today)
        guard needsDownload else { return }

        await download(meta: meta, silent: true)
    }

    // MARK: - Download

    func startDownload(meta: GtfsMeta?) {
        guard downloadTask == nil else { return }
        downloadTask = Task { [weak self] in
            await self?.download(meta: meta, silent: false)
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progress = nil
    }

    private func download(meta: GtfsMeta?, silent: Bool) async {
        let today = ServiceDay.ymd()
        let days = scope.days(from: today, serviceRange: meta?.serviceRange)
        guard !days.isEmpty else { return }

        errorMessage = nil
        // A new GTFS release moves times, so the old pack is not merged with
        // the new one — it is replaced.
        if !manifest.feedVersion.isEmpty, manifest.feedVersion != (meta?.feedVersion ?? manifest.feedVersion) {
            OfflineScheduleStore.removeAll()
        }

        let previous = manifest.days
        var stored: [String] = []
        var failures = 0
        var lastError: Error?

        for (offset, day) in days.enumerated() {
            guard !Task.isCancelled else { break }
            progress = Progress(dayNumber: offset + 1, dayCount: days.count, completed: 0, total: 1)

            do {
                try await downloadDay(day, feedVersion: meta?.feedVersion ?? "")
                stored.append(day)
            } catch is CancellationError {
                break
            } catch {
                // One bad day does not sink the rest — a rider with six days
                // is better off than a rider with none.
                failures += 1
                lastError = error
            }
        }

        let cancelled = Task.isCancelled
        progress = nil
        downloadTask = nil

        if !stored.isEmpty {
            // A finished download defines the pack exactly, so days outside it
            // are pruned. A cancelled one does not: the rider stopped it, they
            // did not ask to lose the days they already had.
            let keep = cancelled ? Set(stored).union(previous) : Set(stored)
            OfflineScheduleStore.removeDays(notIn: keep)
            OfflineScheduleStore.writeManifest(
                OfflineScheduleManifest(
                    feedVersion: meta?.feedVersion ?? manifest.feedVersion,
                    days: keep.sorted(),
                    builtAt: Date(),
                    bytes: OfflineScheduleStore.byteSize()
                )
            )
            manifest = OfflineScheduleStore.manifest
            await refreshBytes()
            // The widget reads the same pack; it should notice immediately
            // rather than at its next scheduled reload.
            WidgetCenter.shared.reloadAllTimelines()
        }

        guard !cancelled, !silent else { return }

        if stored.isEmpty {
            errorMessage = lastError?.localizedDescription
                ?? "A menetrend letöltése nem sikerült. Ellenőrizd a hálózatot."
        } else if failures > 0 {
            errorMessage = "\(failures) nap nem jött le; a többi elérhető offline."
        }
    }

    /// One service day: the route list, every direction's board, and the
    /// per-stop index built from them.
    private func downloadDay(_ ymd: String, feedVersion: String) async throws {
        let routesData = try await APIClient.shared.timetableRoutesData(date: ymd)
        let routes = try JSONDecoder().decode(TimetableRoutesResponse.self, from: routesData)
        OfflineScheduleStore.writeTimetableRoutes(routesData, ymd: ymd)

        let pairs = routes.routes.flatMap { route in
            route.directions.map { (routeId: route.id, dir: $0.dir) }
        }
        guard !pairs.isEmpty else { throw OfflineScheduleError.emptyDay }

        progress = Progress(
            dayNumber: progress?.dayNumber ?? 1,
            dayCount: progress?.dayCount ?? 1,
            completed: 0,
            total: pairs.count
        )

        var builder = OfflineScheduleIndexBuilder(date: ymd, feedVersion: feedVersion)
        var completed = 0

        // A task group with a fixed width: the boards come back in whatever
        // order they finish, and the builder folds them in on the main actor
        // one at a time, which keeps it a plain value type.
        try await withThrowingTaskGroup(of: (String, String, Data)?.self) { group in
            var next = 0

            func addTask() {
                guard next < pairs.count else { return }
                let pair = pairs[next]
                next += 1
                group.addTask {
                    guard let data = try? await APIClient.shared.timetableData(
                        routeId: pair.routeId, dir: pair.dir, date: ymd
                    ) else { return nil }
                    return (pair.routeId, pair.dir, data)
                }
            }

            for _ in 0..<min(Self.parallelism, pairs.count) { addTask() }

            while let finished = try await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    throw CancellationError()
                }
                if let (routeId, dir, data) = finished {
                    OfflineScheduleStore.writeTimetable(data, routeId: routeId, dir: dir, ymd: ymd)
                    if let table = try? JSONDecoder().decode(TimetableResponse.self, from: data) {
                        builder.add(table)
                    }
                }
                completed += 1
                progress?.completed = completed
                addTask()
            }
        }

        guard builder.tripCount > 0 else { throw OfflineScheduleError.emptyDay }

        // Transposing a weekday is 48 000 stop times to sort and a third of a
        // megabyte to encode. Off the main actor, or the progress bar it is
        // driving stops moving.
        let folded = builder
        await Task.detached(priority: .utility) {
            OfflineScheduleStore.writeIndex(folded.build(), ymd: ymd)
        }.value
    }

    // MARK: - Housekeeping

    func deleteAll() {
        OfflineScheduleStore.removeAll()
        manifest = OfflineScheduleStore.manifest
        bytes = 0
        errorMessage = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshBytes() async {
        bytes = await Task.detached(priority: .utility) {
            OfflineScheduleStore.byteSize()
        }.value
        manifest = OfflineScheduleStore.manifest
    }
}
