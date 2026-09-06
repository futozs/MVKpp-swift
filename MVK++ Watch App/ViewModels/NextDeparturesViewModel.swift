//
//  NextDeparturesViewModel.swift
//  MVK++ Watch App
//

import Combine
import Foundation
import WidgetKit

@MainActor
final class NextDeparturesViewModel: ObservableObject {
    @Published private(set) var results: [String: StopArrivalsResponse] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func refresh(stopIds: [String]) async {
        guard !stopIds.isEmpty else {
            results = [:]
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.multiArrivals(stopIds: stopIds)
            for stopResult in response.results {
                results[stopResult.stop.id] = stopResult
            }
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Nem sikerült frissíteni az érkezéseket"
        }
    }
}
