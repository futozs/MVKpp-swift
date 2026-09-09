//
//  StopDetailSheet.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

/// What is coming to one stop. Opened by tapping a dot on the map, and kept
/// deliberately short — it sits over the map, and the rider still needs to see
/// where the bus is.
struct StopDetailSheet: View {
    let stop: Stop
    let isMonitored: Bool
    var onToggleMonitor: (String) -> Void
    var onFocusTrip: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = StopArrivalsModel()

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.errorMessage {
                    ScrollView { ErrorNotice(message: error).padding(16) }
                } else if model.isLoading && model.arrivals.isEmpty {
                    ProgressView("Indulások lekérése…")
                        .font(Theme.mono(12, weight: .regular))
                        .tint(Theme.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.arrivals.isEmpty {
                    ContentUnavailableView(
                        "Nincs közelgő indulás",
                        systemImage: "clock.badge.xmark",
                        description: Text("Erről a megállóról jelenleg nincs ismert indulás.")
                    )
                } else {
                    List(model.arrivals) { arrival in
                        ArrivalRowView(arrival: arrival) { tripId, vehicleId in
                            onFocusTrip(tripId, vehicleId)
                            dismiss()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.border)
                    }
                    .listStyle(.plain)
                    .mvkBackground()
                }
            }
            .background(AppBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { header }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onToggleMonitor(stop.id)
                    } label: {
                        Image(systemName: isMonitored ? "checkmark" : "plus")
                    }
                    .tint(isMonitored ? Theme.primary : Theme.foreground)
                    .accessibilityLabel(isMonitored ? "Levétel a figyelőről" : "Felvétel a figyelőre")
                }
            }
            .task(id: stop.id) { await model.start(stopId: stop.id, stopName: stop.name) }
            .onDisappear { model.stop() }
        }
    }

    private var header: some View {
        VStack(spacing: 1) {
            Text(stop.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)

            HStack(spacing: 5) {
                Text(stop.id)
                    .font(Theme.mono(10, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
                Text("·").foregroundStyle(Theme.mutedForeground)
                if model.isOffline {
                    OfflineTag(compact: true)
                } else {
                    LiveTag(live: model.hasLiveData)
                }
            }
        }
    }
}

/// Departures for one stop, refreshed every four seconds while visible.
@MainActor
final class StopArrivalsModel: ObservableObject {
    @Published private(set) var arrivals: [ArrivalItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLiveData = false
    /// The list came out of the downloaded timetable because the gateway
    /// could not be reached. Different from `hasLiveData == false`, which only
    /// means no vehicle is reporting on an otherwise live board.
    @Published private(set) var isOffline = false

    private let pollInterval: TimeInterval = 4
    private var task: Task<Void, Never>?
    /// A single dropped poll on a moving phone is normal; the last good list
    /// is better than an immediate downgrade to schedule times. Past this the
    /// connection is genuinely gone.
    private let staleAfter: TimeInterval = 45
    private var lastSuccessAt: Date?

    func start(stopId: String, stopName: String = "", limit: Int = 16) async {
        stop()
        isLoading = true

        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.load(stopId: stopId, stopName: stopName, limit: limit)
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func load(stopId: String, stopName: String, limit: Int) async {
        do {
            let response = try await APIClient.shared.arrivals(stopId: stopId, limit: limit)
            arrivals = response.arrivals
            // `rtError` set means the gateway fell back to the timetable.
            hasLiveData = response.rtError == nil
            isOffline = false
            errorMessage = nil
            lastSuccessAt = Date()

            // Every refresh also re-aims the stop's alarm at the latest
            // prediction.
            NotificationCenterStore.shared.scheduleAlarm(
                stopId: stopId,
                stopName: stopName.isEmpty ? (response.stop.name ?? stopId) : stopName,
                arrivals: response.arrivals
            )
        } catch {
            fallBackToSchedule(stopId: stopId, stopName: stopName, limit: limit, error: error)
        }
        isLoading = false
    }

    /// No gateway. The downloaded timetable knows when the bus is *supposed*
    /// to come, which is the honest answer and a far better one than a blank
    /// card — every row is marked schedule-only so nobody reads a prediction
    /// into it.
    private func fallBackToSchedule(stopId: String, stopName: String, limit: Int, error: Error) {
        let isStale = lastSuccessAt.map { Date().timeIntervalSince($0) > staleAfter } ?? true
        // Keep the last good list rather than blanking the sheet mid-poll.
        guard isStale || arrivals.isEmpty else { return }

        let scheduled = OfflineDepartures.arrivals(stopId: stopId, limit: limit)
        guard !scheduled.isEmpty else {
            if arrivals.isEmpty || isOffline {
                arrivals = []
                isOffline = OfflineDepartures.isAvailable
                errorMessage = isOffline
                    ? "Nincs kapcsolat, és a letöltött menetrend szerint innen ma már nem indul járat."
                    : error.localizedDescription
            }
            return
        }

        arrivals = scheduled
        hasLiveData = false
        isOffline = true
        errorMessage = nil

        // The alarm is still worth setting: a menetrend szerinti idő is what
        // the rider is planning around when there is nothing better.
        NotificationCenterStore.shared.scheduleAlarm(
            stopId: stopId,
            stopName: stopName.isEmpty ? stopId : stopName,
            arrivals: scheduled
        )
    }

    deinit { task?.cancel() }
}
