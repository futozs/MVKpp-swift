//
//  StopDetailView.swift
//  MVK++ Watch App
//

import SwiftUI

/// Full arrival list for one stop, polled every 4s while visible
/// (auto-cancelled on disappear via `.task`), plus an immediate refresh when
/// the app returns to the foreground. Tapping an arrival "pins" it in
/// TripFollowView (live map + progress + delay).
struct StopDetailView: View {
    let stopId: String
    @StateObject private var viewModel = StopDetailViewModel()
    @Environment(\.scenePhase) private var scenePhase

    private static let pollInterval: Duration = .seconds(4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(contextLabel)
                .font(.footnote)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 4)

            list
        }
        .background(AppBackground())
        .navigationDestination(for: ArrivalItem.self) { arrival in
            TripFollowView(arrival: arrival)
        }
        .task(id: stopId) {
            while !Task.isCancelled {
                await viewModel.refresh(stopId: stopId)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refresh(stopId: stopId) }
            }
        }
    }

    private var list: some View {
        List {
            if let response = viewModel.response {
                if response.arrivals.isEmpty {
                    Text("Nincs induló járat")
                        .foregroundStyle(Theme.mutedForeground)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(response.arrivals) { arrival in
                        NavigationLink(value: arrival) {
                            ArrivalRowView(arrival: arrival)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                if let rtError = response.rtError {
                    Text(rtError)
                        .font(.caption2)
                        .foregroundStyle(Theme.late)
                        .listRowBackground(Color.clear)
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .listRowBackground(Color.clear)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(Theme.late)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var contextLabel: String {
        let name = viewModel.response?.stop.name ?? stopId
        let code = stopId.hasPrefix("SP") ? String(stopId.dropFirst(2)) : stopId
        return "\(name) · \(code)"
    }
}

#Preview {
    NavigationStack {
        StopDetailView(stopId: "SP1")
    }
    .environmentObject(NavigationCoordinator())
}
