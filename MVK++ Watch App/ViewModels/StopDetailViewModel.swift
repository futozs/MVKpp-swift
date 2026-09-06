//
//  StopDetailViewModel.swift
//  MVK++ Watch App
//

import Combine
import Foundation
import WidgetKit

@MainActor
final class StopDetailViewModel: ObservableObject {
    @Published private(set) var response: StopArrivalsResponse?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func refresh(stopId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await APIClient.shared.arrivals(stopId: stopId)
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Nem sikerült frissíteni"
        }
    }
}
