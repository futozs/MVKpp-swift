//
//  TripProgressViewModel.swift
//  MVK++ Watch App
//

import Combine
import Foundation

@MainActor
final class TripProgressViewModel: ObservableObject {
    @Published private(set) var response: TripProgressResponse?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func refresh(tripId: String, vehicleId: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await APIClient.shared.tripProgress(tripId: tripId, vehicleId: vehicleId)
            errorMessage = nil
        } catch {
            errorMessage = "Nem sikerült frissíteni"
        }
    }
}
