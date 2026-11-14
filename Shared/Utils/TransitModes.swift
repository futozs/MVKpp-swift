//
//  TransitModes.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// MVK tram, MVK bus, Volán (intercity coach) and MÁV rail — a port of the
/// web app's `lib/modes.ts`.
///
/// IDs tell the source apart: MVK's carry no prefix (`SP388`), the regional
/// ones come with the MÁV+ prefix (`hkir:` Volán, `1:` rail).
enum TransitMode: String, Codable, CaseIterable, Hashable {
    case tram, bus, coach, rail

    /// "busz", "villamos", "vonat" — the Volán is a bus too.
    var noun: String {
        switch self {
        case .rail: return "vonat"
        case .tram: return "villamos"
        case .bus, .coach: return "busz"
        }
    }
}

enum StopMerge: String, Codable, CaseIterable, Hashable {
    case all, mvk, coach, off
}

enum TransitModes {

    /// `?modes=` value, always in the canonical order.
    static func param(_ modes: [TransitMode]) -> String {
        TransitMode.allCases.filter(modes.contains).map(\.rawValue).joined(separator: ",")
    }

    /// The board key (`tram,bus,coach,rail~all`) — the `?modes=&merge=` query
    /// and the `stop:<id>@<key>` WebSocket topic.
    static func boardKey(_ modes: [TransitMode], merge: StopMerge) -> String {
        "\(param(modes))~\(merge.rawValue)"
    }

    static func hasRegional(_ modes: [TransitMode]) -> Bool {
        modes.contains(.coach) || modes.contains(.rail)
    }

    enum Feed: String { case mvk, coach, rail }

    /// The source of an ID: MVK (no prefix), Volán (`hkir:`), rail (`1:`).
    static func feed(ofId id: String) -> Feed {
        guard id.contains(":") else { return .mvk }
        return id.hasPrefix("1:") ? .rail : .coach
    }

    static func isRegionalId(_ id: String) -> Bool { id.contains(":") }

    /// In the merged view a Volán twin stop is not a separate item.
    static func isMergedTwin(_ stop: Stop, merge: StopMerge) -> Bool {
        stop.twinOf != nil && merge != .off
    }

    /// A vehicle's mode; native MVK vehicles do not carry one, so it comes
    /// from the route type.
    static func vehicleMode(_ vehicle: LiveVehicle, routeType: String?) -> TransitMode {
        if let raw = vehicle.mode, let mode = TransitMode(rawValue: raw) { return mode }
        switch feed(ofId: vehicle.id) {
        case .coach: return .coach
        case .rail: return .rail
        case .mvk: return routeType == "900" || routeType == "0" || vehicle.label == "TRAM" ? .tram : .bus
        }
    }

    static func routeMode(_ route: Route) -> TransitMode {
        if let raw = route.mode, let mode = TransitMode(rawValue: raw) { return mode }
        switch feed(ofId: route.id) {
        case .coach: return .coach
        case .rail: return .rail
        case .mvk: return route.type == "900" || route.type == "0" ? .tram : .bus
        }
    }

    // MARK: - Vehicle identifiers

    /// Rolling-stock class (digits 5–8 of the 12-digit UIC number) → the
    /// everyday name.
    private static let railClass: [String: String] = [
        "1815": "KISS", "1415": "FLIRT", "1416": "Desiro", "0117": "Bzmot",
        "0418": "M41", "0628": "M62", "0431": "V43", "0432": "V43", "0433": "V43",
        "0630": "V63", "0470": "Taurus", "0480": "TRAXX",
    ]
    private static let foreignClass: [String: String] = ["182": "Taurus", "193": "Vectron"]

    struct RailVehicle {
        let full: String
        let short: String
        let model: String?
    }

    static func railVehicle(_ id: String) -> RailVehicle? {
        guard id.hasPrefix("1:") else { return nil }
        let digits = Array(id.dropFirst(2))
        guard digits.count == 12, digits.allSatisfy(\.isNumber) else { return nil }
        let s = String(digits)
        func part(_ from: Int, _ len: Int) -> String {
            let start = s.index(s.startIndex, offsetBy: from)
            return String(s[start..<s.index(start, offsetBy: len)])
        }
        let country = part(0, 2), operatorCode = part(2, 2), series = part(4, 4), number = part(8, 3), check = part(11, 1)
        let cls = String(series.dropFirst())
        let model = operatorCode == "55" ? railClass[series] : foreignClass[cls]
        return RailVehicle(full: "\(country) \(operatorCode) \(series) \(number)-\(check)", short: "\(cls) \(number)", model: model)
    }

    /// `RWE771` → `RWE-771`, the new four-letter `AAJB306` → `AA JB-306`.
    private static func plateText(_ raw: String) -> String {
        let chars = Array(raw)
        if chars.count == 7, chars[0..<4].allSatisfy(\.isUppercase), chars[4..<7].allSatisfy(\.isNumber) {
            return "\(String(chars[0..<2])) \(String(chars[2..<4]))-\(String(chars[4..<7]))"
        }
        if chars.count == 6, chars[0..<3].allSatisfy(\.isUppercase), chars[3..<6].allSatisfy(\.isNumber) {
            return "\(String(chars[0..<3]))-\(String(chars[3..<6]))"
        }
        return raw
    }

    /// The displayable vehicle ID: MVK's fleet number as is, a Volán bus by
    /// its plate, a train by type, class and number (`KISS 815 038`).
    static func displayVehicleId(_ id: String, plate: String? = nil) -> String {
        guard isRegionalId(id) else { return id }
        if let rail = railVehicle(id) {
            return rail.model.map { "\($0) \(rail.short)" } ?? rail.short
        }
        var raw = plate ?? ""
        if raw.isEmpty {
            raw = id.replacingOccurrences(of: "hkir:hkir_", with: "")
            if raw.hasPrefix("1:") { raw.removeFirst(2) }
        }
        return plateText(raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: ""))
    }
}
