//
//  WatchMapView.swift
//  MVK++ Watch App
//

import MapKit
import SwiftUI

/// Térkép: the stops and the live vehicles around the rider. Only what is
/// near the camera is drawn — a wrist has no room for the whole city, and
/// MapKit on watchOS slows down quickly with annotations.
struct WatchMapView: View {
    @EnvironmentObject private var location: LocationProvider
    @EnvironmentObject private var catalog: StopsCatalog
    @EnvironmentObject private var router: WatchRouter
    @EnvironmentObject private var link: WatchLink
    @StateObject private var vehicles = VehicleFeed()
    @State private var position: MapCameraPosition = .userLocation(fallback: .camera(Self.cityCamera))
    @State private var center = Self.cityCenter
    @State private var spanKm = 1.2

    private static let cityCenter = CLLocationCoordinate2D(latitude: 48.1035, longitude: 20.7784)
    private static let cityCamera = MapCamera(centerCoordinate: cityCenter, distance: 1800, heading: 0, pitch: 0)
    private static let maxStops = 40
    private static let maxVehicles = 30

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            UserAnnotation()
            ForEach(visibleStops) { stop in
                Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon), anchor: .center) {
                    Button {
                        router.push(.stop(stop.id))
                    } label: {
                        Circle()
                            .fill(Theme.background)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Theme.primary, lineWidth: 2))
                            .padding(6)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
            ForEach(visibleVehicles) { vehicle in
                if let coordinate = vehicle.coordinate {
                    Annotation(vehicle.routeShort, coordinate: coordinate, anchor: .center) {
                        Button {
                            router.push(.trip(TripRef(vehicle: vehicle)))
                        } label: {
                            RouteTile(short: vehicle.routeShort, colorHex: vehicle.routeColor, textHex: vehicle.routeText, size: .small)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            center = context.region.center
            spanKm = max(0.3, context.region.span.latitudeDelta * 111)
        }
        .navigationTitle("Térkép")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            location.start()
            vehicles.start(modes: link.settings.modesParam)
        }
        .onDisappear { vehicles.stop() }
    }

    private var radiusKm: Double { spanKm * 0.75 }

    private var visibleStops: [Stop] {
        guard spanKm < 4 else { return [] }
        return catalog.stops
            .filter { Geo.distanceKm(center.latitude, center.longitude, $0.lat, $0.lon) < radiusKm }
            .prefix(Self.maxStops)
            .map { $0 }
    }

    private var visibleVehicles: [LiveVehicle] {
        vehicles.vehicles
            .compactMap { vehicle -> (LiveVehicle, Double)? in
                guard let lat = vehicle.lat, let lon = vehicle.lon else { return nil }
                let distance = Geo.distanceKm(center.latitude, center.longitude, lat, lon)
                return distance < radiusKm * 1.5 ? (vehicle, distance) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(Self.maxVehicles)
            .map(\.0)
    }
}
