//
//  TextUtils.swift
//  MVK++ (shared by the Watch, Phone and Widget targets)
//

import Foundation

extension String {
    /// Folds accents and lowercases, so "Újgyőri" matches a typed "ujgyori".
    /// Every stop/vehicle search in the app compares normalized text.
    var normalizedForSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "hu_HU"))
    }

    func containsNormalized(_ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        return normalizedForSearch.contains(needle.normalizedForSearch)
    }
}

enum HungarianText {

    private static let tensSuffix: [Int: String] = [
        1: "es", 2: "as", 3: "as", 4: "es", 5: "es", 6: "as", 7: "es", 8: "as", 9: "es",
    ]

    private static let onesSuffix: [Int: String] = [
        1: "es", 2: "es", 3: "as", 4: "es", 5: "ös", 6: "os", 7: "es", 8: "as", 9: "es",
    ]

    /// "1" → "1-es", "35" → "35-ös", "20" → "20-as". Used wherever a route
    /// number is read out as a word ("a 2-es villamos"), never on the tiles
    /// themselves. Non-numeric route names pass through untouched.
    static func withSuffix(_ routeShort: String) -> String {
        let trimmed = routeShort.trimmingCharacters(in: .whitespaces)
        guard let n = Int(trimmed), String(n) == trimmed else { return routeShort }
        if n == 100 { return "\(routeShort)-as" }

        let ones = n % 10
        if ones == 0 {
            let tens = (n / 10) % 10
            return "\(routeShort)-\(tensSuffix[tens] ?? "es")"
        }
        return "\(routeShort)-\(onesSuffix[ones] ?? "es")"
    }
}
