//
//  TransitModes.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// MVK tram, MVK bus, Volán (regional coach) and rail — the web app's
/// `lib/modes.ts`. MVK ids carry no prefix (`SP388`); regional ones come with
/// MÁV+'s (`hkir:` Volán, `1:` rail), so the source can be read off an id.
enum TransitMode: String, Codable, CaseIterable, Hashable {
    case tram, bus, coach, rail

    /// The per-mode switch the web keeps in localStorage (`mvk_pref_mode_*`).
    var preferenceKey: String { "mvk_pref_mode_\(rawValue)" }

    /// Enabled modes now. At least tram and bus always stay on.
    static func enabled(_ defaults: UserDefaults = .standard) -> [TransitMode] {
        let on = allCases.filter { mode in
            guard let raw = defaults.object(forKey: mode.preferenceKey) else { return true }
            if let flag = raw as? Bool { return flag }
            return (raw as? String) != "false"
        }
        return on.isEmpty ? [.tram, .bus] : on
    }

    /// The `?modes=` value.
    static func param(_ modes: [TransitMode] = enabled()) -> String {
        allCases.filter { modes.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    static func hasRegional(_ modes: [TransitMode]) -> Bool {
        modes.contains(.coach) || modes.contains(.rail)
    }

    /// „busz”, „villamos”, „vonat” — a Volán coach is a bus too.
    var noun: String {
        switch self {
        case .rail: return "vonat"
        case .tram: return "villamos"
        case .bus, .coach: return "busz"
        }
    }

    /// The vehicle's name inflected for sentences: „erre a buszra”, „ezen a buszon”.
    struct Words {
        let n: String
        let ra: String
        let on: String
        let om: String
        let val: String
    }

    var words: Words {
        switch self {
        case .tram: return Words(n: "villamos", ra: "villamosra", on: "villamoson", om: "villamosom", val: "villamossal")
        case .bus, .coach: return Words(n: "busz", ra: "buszra", on: "buszon", om: "buszom", val: "busszal")
        case .rail: return Words(n: "vonat", ra: "vonatra", on: "vonaton", om: "vonatom", val: "vonattal")
        }
    }

    /// How close phone and vehicle count as "together", in metres. A bus is a
    /// point; a train is a 100–200 m consist whose signal lags 10–40 s.
    /// near/far: boarding detection; withBus/away: during a ride; atStop: standing at a stop.
    struct Proximity {
        let near: Double
        let far: Double
        let withBus: Double
        let away: Double
        let atStop: Double
    }

    var proximity: Proximity {
        switch self {
        case .tram, .bus: return Proximity(near: 50, far: 150, withBus: 200, away: 300, atStop: 70)
        case .coach: return Proximity(near: 80, far: 250, withBus: 300, away: 450, atStop: 90)
        case .rail: return Proximity(near: 220, far: 600, withBus: 500, away: 900, atStop: 300)
        }
    }
}

enum TransitFeed: String {
    case mvk, coach, rail

    static func of(id: String) -> TransitFeed {
        guard id.contains(":") else { return .mvk }
        return id.hasPrefix("1:") ? .rail : .coach
    }
}

enum TransitIds {
    static func isRegional(_ id: String) -> Bool { id.contains(":") }

    /// A vehicle or trip's mode from its ids alone (tram and bus are one here).
    static func rideMode(vehicleId: String, tripId: String? = nil) -> TransitMode {
        let id = (tripId?.isEmpty == false ? tripId : nil) ?? vehicleId
        switch TransitFeed.of(id: id) {
        case .mvk: return .bus
        case .coach: return .coach
        case .rail: return .rail
        }
    }

    static func vehicleMode(id: String, mode: TransitMode?, label: String? = nil, routeType: String? = nil) -> TransitMode {
        if let mode { return mode }
        switch TransitFeed.of(id: id) {
        case .coach: return .coach
        case .rail: return .rail
        case .mvk: return routeType == "900" || routeType == "0" || label == "TRAM" ? .tram : .bus
        }
    }

    private static let railClass: [String: String] = [
        "1815": "KISS", "1415": "FLIRT", "1416": "Desiro", "0117": "Bzmot", "0418": "M41",
        "0628": "M62", "0431": "V43", "0432": "V43", "0433": "V43", "0630": "V63",
        "0470": "Taurus", "0480": "TRAXX",
    ]
    private static let foreignClass: [String: String] = ["182": "Taurus", "193": "Vectron"]

    struct RailVehicle {
        let full: String
        let short: String
        let model: String?
    }

    /// A rail vehicle from its UIC number: `92 55 0418 322-7`, `418 322`, `M41`.
    static func railVehicle(_ id: String) -> RailVehicle? {
        guard id.hasPrefix("1:") else { return nil }
        let digits = Array(id.dropFirst(2))
        guard digits.count == 12, digits.allSatisfy(\.isNumber) else { return nil }
        let a = String(digits[0..<2]), b = String(digits[2..<4]), c = String(digits[4..<8])
        let d = String(digits[8..<11]), e = String(digits[11])
        let cls = String(c.dropFirst())
        let model = b == "55" ? railClass[c] : foreignClass[cls]
        return RailVehicle(full: "\(a) \(b) \(c) \(d)-\(e)", short: "\(cls) \(d)", model: model)
    }

    private static func plateText(_ raw: String) -> String {
        let chars = Array(raw)
        let letters = { (r: Range<Int>) in chars[r].allSatisfy { $0.isLetter && $0.isUppercase } }
        let numbers = { (r: Range<Int>) in chars[r].allSatisfy(\.isNumber) }
        if chars.count == 7, letters(0..<4), numbers(4..<7) {
            return "\(String(chars[0..<2])) \(String(chars[2..<4]))-\(String(chars[4..<7]))"
        }
        if chars.count == 6, letters(0..<3), numbers(3..<6) {
            return "\(String(chars[0..<3]))-\(String(chars[3..<6]))"
        }
        return raw
    }

    /// The vehicle id riders read: MVK fleet number as is, a Volán coach's
    /// plate, a train's type, class and number.
    static func displayVehicleId(_ id: String, plate: String? = nil) -> String {
        guard isRegional(id) else { return id }
        if let rail = railVehicle(id) {
            return rail.model.map { "\($0) \(rail.short)" } ?? rail.short
        }
        let base = plate?.isEmpty == false ? plate ?? id : id
            .replacingOccurrences(of: "hkir:hkir_", with: "")
            .replacingOccurrences(of: "1:", with: "")
        return plateText(base.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: ""))
    }

    /// The full id for the popup: a train's UIC number, otherwise the display id.
    static func vehicleIdTitle(_ id: String, plate: String? = nil) -> String {
        if let rail = railVehicle(id) {
            return "\(rail.model.map { "\($0) · " } ?? "")\(rail.full)"
        }
        return displayVehicleId(id, plate: plate)
    }
}

extension LiveVehicle {
    func transitMode(routes: [String: Route]) -> TransitMode {
        TransitIds.vehicleMode(id: id, mode: mode, label: label, routeType: routes[routeId]?.type)
    }

    var rideMode: TransitMode { mode ?? TransitIds.rideMode(vehicleId: id, tripId: tripId) }
}

enum StopMerge: String, Codable, CaseIterable, Hashable {
    case all, mvk, coach, off
}

enum TransitModes {

    /// `?modes=` value, always in the canonical order.
    static func param(_ modes: [TransitMode]) -> String {
        TransitMode.param(modes)
    }

    /// The board key (`tram,bus,coach,rail~all`) — the `?modes=&merge=` query
    /// and the `stop:<id>@<key>` WebSocket topic.
    static func boardKey(_ modes: [TransitMode], merge: StopMerge) -> String {
        "\(param(modes))~\(merge.rawValue)"
    }

    /// A board key back as `?modes=&merge=`.
    static func boardQueryItems(_ key: String) -> [URLQueryItem] {
        let parts = key.split(separator: "~", maxSplits: 1).map(String.init)
        var items = [URLQueryItem(name: "modes", value: parts.first ?? TransitMode.param())]
        if parts.count > 1 { items.append(URLQueryItem(name: "merge", value: parts[1])) }
        return items
    }

    static func hasRegional(_ modes: [TransitMode]) -> Bool {
        TransitMode.hasRegional(modes)
    }

    typealias Feed = TransitFeed

    static func feed(ofId id: String) -> Feed { TransitFeed.of(id: id) }

    static func isRegionalId(_ id: String) -> Bool { TransitIds.isRegional(id) }

    /// In the merged view a Volán twin stop is not a separate item.
    static func isMergedTwin(_ stop: Stop, merge: StopMerge) -> Bool {
        stop.twinOf != nil && merge != .off
    }

    static func vehicleMode(_ vehicle: LiveVehicle, routeType: String?) -> TransitMode {
        TransitIds.vehicleMode(id: vehicle.id, mode: vehicle.mode, label: vehicle.label, routeType: routeType)
    }

    static func routeMode(_ route: Route) -> TransitMode {
        if let mode = route.mode { return mode }
        switch TransitFeed.of(id: route.id) {
        case .coach: return .coach
        case .rail: return .rail
        case .mvk: return route.type == "900" || route.type == "0" ? .tram : .bus
        }
    }

    typealias RailVehicle = TransitIds.RailVehicle

    static func railVehicle(_ id: String) -> RailVehicle? { TransitIds.railVehicle(id) }

    static func displayVehicleId(_ id: String, plate: String? = nil) -> String {
        TransitIds.displayVehicleId(id, plate: plate)
    }
}
