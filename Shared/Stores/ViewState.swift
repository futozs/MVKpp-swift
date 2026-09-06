//
//  ViewState.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

enum AppTab: String, Codable, CaseIterable {
    case map, multistop, timetable, planner, settings
}

/// Where the rider left off. Restored on launch so reopening the app lands
/// where they were, not on a default screen.
///
/// Two different ages apply: the tab and selected stop survive a work day,
/// while an active vehicle follow expires in 45 minutes — resuming a
/// three-hour-old chase would be nonsense.
enum ViewStateStore {

    private static let viewKey = "mvk_view_state"
    private static let mapKey = "mvk_map_view"
    private static let timetableKey = "mvk_timetable_view"

    private static let maxAge: TimeInterval = 8 * 3600
    private static let focusMaxAge: TimeInterval = 45 * 60

    // MARK: - Payloads

    struct ViewState: Codable {
        var tab: AppTab
        var selectedStopId: String?
        var focusTripId: String?
        var focusVehicleId: String?
    }

    struct MapView: Codable {
        var lat: Double
        var lon: Double
        var zoom: Double
    }

    struct TimetableView: Codable {
        var routeId: String?
        var dir: String
        var tripId: String?
    }

    // MARK: - Envelope

    private struct Stored<T: Codable>: Codable {
        let at: Double
        let data: T
    }

    private static func read<T: Codable>(_ key: String, maxAgeSec: TimeInterval) -> (data: T, ageSec: TimeInterval)? {
        guard let raw = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored<T>.self, from: raw)
        else { return nil }
        let age = Date().timeIntervalSince1970 - stored.at
        guard age <= maxAgeSec else { return nil }
        return (stored.data, age)
    }

    private static func write<T: Codable>(_ key: String, _ data: T) {
        let stored = Stored(at: Date().timeIntervalSince1970, data: data)
        guard let encoded = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    // MARK: - View

    static func initialView() -> ViewState? {
        guard let (data, age) = read(viewKey, maxAgeSec: maxAge) as (data: ViewState, ageSec: TimeInterval)? else {
            return nil
        }
        let keepFocus = age <= focusMaxAge
        return ViewState(
            tab: data.tab,
            selectedStopId: data.selectedStopId,
            focusTripId: keepFocus ? data.focusTripId : nil,
            focusVehicleId: keepFocus ? data.focusVehicleId : nil
        )
    }

    static func save(_ state: ViewState) { write(viewKey, state) }

    // MARK: - Map camera

    static func initialMapView() -> MapView? {
        (read(mapKey, maxAgeSec: maxAge) as (data: MapView, ageSec: TimeInterval)?)?.data
    }

    static func save(_ view: MapView) { write(mapKey, view) }

    // MARK: - Timetable selection

    static func initialTimetableView() -> TimetableView? {
        guard let stored = read(timetableKey, maxAgeSec: maxAge) as (data: TimetableView, ageSec: TimeInterval)?,
              stored.data.routeId != nil
        else { return nil }
        return stored.data
    }

    static func save(_ view: TimetableView) { write(timetableKey, view) }

    // MARK: - Filters

    private static let filterKey = "mvk_filter_state"

    static func loadFilters() -> FilterState {
        guard let raw = UserDefaults.standard.data(forKey: filterKey),
              let decoded = try? JSONDecoder().decode(FilterState.self, from: raw)
        else { return .default }
        return decoded
    }

    static func save(_ filters: FilterState) {
        guard let encoded = try? JSONEncoder().encode(filters) else { return }
        UserDefaults.standard.set(encoded, forKey: filterKey)
    }
}
