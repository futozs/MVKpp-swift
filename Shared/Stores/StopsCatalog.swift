//
//  StopsCatalog.swift
//  MVK++ Watch App
//

import Combine
import Foundation

/// The full stop list, fetched once per app session and held in memory for
/// on-device search (a few hundred stops — cheap to keep resident).
@MainActor
final class StopsCatalog: ObservableObject {
    @Published private(set) var stops: [Stop] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stops = try await APIClient.shared.stops()
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
