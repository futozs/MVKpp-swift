//
//  TripFollowView.swift
//  MVK++ Watch App
//

import MapKit
import SwiftUI

/// "Pin" a specific trip: a full-screen live map — tiny stop dots, the
/// route line, and the vehicle zoomed in close — with a minimal HUD
/// (route, signed delay, vehicle id) floating over the bottom edge.
struct TripFollowView: View {
    let arrival: ArrivalItem
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @StateObject private var viewModel = TripProgressViewModel()
    @State private var routeShape: [CLLocationCoordinate2D] = []
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// The rider's camera wins. Data keeps refreshing every 4 s either way,
    /// but once they pan or zoom with the crown the map stops snapping back
    /// to the vehicle — they decide what they are looking at.
    @State private var isFollowingVehicle = true
    @State private var lastRecenterTarget: CLLocationCoordinate2D?
    @State private var lastRecenterAt: Date = .distantPast

    private static let pollInterval: Duration = .seconds(4)
    private static let followDistance: CLLocationDistance = 600
    /// A camera change this soon after — and this close to — one we asked for
    /// is the map settling into our own recenter, not the rider moving it.
    private static let recenterGrace: TimeInterval = 2
    private static let recenterToleranceKm = 0.05

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(viewModel.response?.stops ?? []) { stop in
                if let lat = stop.lat, let lon = stop.lon {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                        Circle()
                            .fill(Theme.mutedForeground)
                            .frame(width: 4, height: 4)
                    }
                }
            }
            if routeShape.count > 1 {
                MapPolyline(coordinates: routeShape)
                    .stroke(Theme.hex(arrival.color), lineWidth: 3)
            }
            if let vehicle = viewModel.response?.vehicle {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: vehicle.lat, longitude: vehicle.lon)) {
                    RouteTile(short: arrival.route, colorHex: arrival.color, textHex: arrival.text, size: .small)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .onMapCameraChange(frequency: .onEnd) { context in
            guard isFollowingVehicle, lastRecenterTarget != nil else { return }
            guard !isOurRecenter(context.camera) else { return }
            isFollowingVehicle = false
        }
        .overlay(alignment: .bottom) {
            hud
        }
        .overlay(alignment: .topTrailing) {
            if !isFollowingVehicle {
                recenterButton
            }
        }
        .task(id: arrival.tripId) {
            async let path: Void = loadPath()
            async let progress: Void = pollProgress()
            _ = await (path, progress)
        }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                RouteTile(short: arrival.route, colorHex: arrival.color, textHex: arrival.text, size: .small)
                DelayIndicator(delaySec: viewModel.response?.scheduleDeviationSec ?? arrival.delaySec)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if let vehicleId = arrival.vehicle?.id ?? viewModel.response?.vehicle?.id {
                    Text("#\(vehicleId)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .fixedSize()
                }
                if let speedKmh {
                    Text("\(Int(speedKmh.rounded())) km/h")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 0)
            }
            if let nextStop = viewModel.response?.nextStop {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(nextStop.name)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 18)
        .padding(.horizontal, 4)
        .offset(y: 16)
        .contentShape(Rectangle())
        .onTapGesture {
            coordinator.popToRoot()
        }
    }

    private var recenterButton: some View {
        Button {
            isFollowingVehicle = true
            recenterOnVehicle()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.primary)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 14, padding: 7)
        .padding(.trailing, 6)
        .padding(.top, 2)
    }

    private var speedKmh: Double? {
        guard let speed = viewModel.response?.vehicle?.speed else { return nil }
        return speed * 3.6
    }

    private func loadPath() async {
        guard let path = try? await APIClient.shared.tripPath(tripId: arrival.tripId, vehicleId: arrival.vehicle?.id) else { return }
        routeShape = path.shape.compactMap { point in
            guard point.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
        }
    }

    /// Keeps polling on its own clock regardless of the camera — a rider who
    /// zoomed out still gets fresh vehicle, delay and next-stop data.
    private func pollProgress() async {
        while !Task.isCancelled {
            await viewModel.refresh(tripId: arrival.tripId, vehicleId: arrival.vehicle?.id)
            if isFollowingVehicle {
                recenterOnVehicle()
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func recenterOnVehicle() {
        guard let vehicle = viewModel.response?.vehicle else { return }
        let center = CLLocationCoordinate2D(latitude: vehicle.lat, longitude: vehicle.lon)
        lastRecenterTarget = center
        lastRecenterAt = .now
        // Explicit heading/pitch of 0 — watchOS's map renderer doesn't
        // support 3D pitch, and letting `.region(_:)` derive an implicit
        // camera was triggering "MKMapView pitch cannot be enabled on this
        // device" and hanging the view.
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: center,
                distance: Self.followDistance,
                heading: 0,
                pitch: 0
            )
        )
    }

    /// Distinguishes the map echoing our own recenter from a real gesture.
    /// The map can clamp the distance it was handed, so only the centre is
    /// compared, inside a short window after we asked for the move.
    private func isOurRecenter(_ camera: MapCamera) -> Bool {
        guard let target = lastRecenterTarget,
              Date.now.timeIntervalSince(lastRecenterAt) < Self.recenterGrace
        else { return false }
        return Geo.distanceKm(target, camera.centerCoordinate) < Self.recenterToleranceKm
    }
}
