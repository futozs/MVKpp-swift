//
//  Lenient.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

/// One element of a feed list or map, decoded on its own. The live feeds mix
/// three operators' data; one vehicle or run the app cannot read must drop
/// out alone instead of failing the whole push — the web app's JSON.parse
/// never rejects a list for one odd entry either.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension Array where Element: Decodable {
    init(lenient items: [Lenient<Element>]) {
        self = items.compactMap { $0.value }
    }
}

extension Dictionary where Key == String, Value: Decodable {
    init(lenient items: [String: Lenient<Value>]) {
        self = items.compactMapValues { $0.value }
    }
}

extension KeyedDecodingContainer {
    /// A string the server may also send as a number (vehicle and trip ids).
    func lenientString(_ key: Key) -> String? {
        if let text = try? decodeIfPresent(String.self, forKey: key) { return text }
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return String(number) }
        return nil
    }

    /// Whole seconds the server may send with a fraction (JS numbers).
    func lenientInt(_ key: Key) -> Int? {
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return number }
        if let number = try? decodeIfPresent(Double.self, forKey: key), number.isFinite { return Int(number.rounded()) }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        (try? decodeIfPresent(Double.self, forKey: key)) ?? nil
    }

    /// An optional field whose value this build may not know (a new mode).
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
