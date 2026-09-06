//
//  APIConfig.swift
//  MVK++ Watch App
//

import Foundation

/// Single source of truth for the MVK gateway address.
/// Change `baseURLString` here and every request in the app repoints automatically.
enum APIConfig {
    static let baseURLString = "https://mvk.futozs.hu"

    static var baseURL: URL {
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid APIConfig.baseURLString: \(baseURLString)")
        }
        return url
    }
}
