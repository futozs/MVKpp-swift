//
//  MapCamera.swift
//  MVK++ Phone App
//

import Combine
import MapKit

/// A camera move requested from SwiftUI. The map consumes one and clears it,
/// so the same command can be issued again later.
enum MapCommand: Equatable {
    /// Animated move to a point at a Leaflet-style zoom level.
    case fly(CLLocationCoordinate2D, zoom: Double)
    /// Immediate move, no animation — used when following a vehicle so the
    /// view is already correct by the time the next position arrives.
    case jump(CLLocationCoordinate2D, zoom: Double)
    /// Frame all points, never zooming in past `maxZoom`.
    case fit([CLLocationCoordinate2D], maxZoom: Double)
    /// Move only if the current zoom is further out than `minZoom`.
    case flyAtLeast(CLLocationCoordinate2D, minZoom: Double)

    static func == (lhs: MapCommand, rhs: MapCommand) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}

/// Holds at most one pending camera move.
///
/// The queue is deliberately *not* `@Published`: the map drains it from inside
/// `updateUIView`, and clearing a published property there would republish
/// mid-update and spin the view loop. `generation` is the only observable
/// part, and it only ever changes from an event handler.
@MainActor
final class MapCameraController: ObservableObject {
    @Published private(set) var generation = 0

    private(set) var pending: MapCommand?
    /// Latest known zoom, updated by the map. Read-only bookkeeping — nothing
    /// observes it, so it stays unpublished.
    private(set) var zoom: Double = 13

    func send(_ command: MapCommand) {
        pending = command
        generation &+= 1
    }

    /// Takes the pending command, if any. Safe to call during a view update.
    func consume() -> MapCommand? {
        defer { pending = nil }
        return pending
    }

    func updateZoom(_ value: Double) {
        zoom = value
    }
}

extension MKMapView {

    /// The view width the zoom maths needs. Before the first layout pass
    /// `bounds` is zero, and using it would put the camera at an absurd zoom —
    /// the screen width is the right stand-in until layout happens.
    private var zoomReferenceWidth: CGFloat {
        bounds.width > 1 ? bounds.width : 390
    }

    /// Leaflet-style zoom levels, so the ported view logic ("zoom 16 on me",
    /// "at least 17 when a stop is selected") keeps its original numbers.
    var zoomLevel: Double {
        log2(360 * (zoomReferenceWidth / 256) / region.span.longitudeDelta)
    }

    /// `maxZoom` keeps callers like `.fit` from zooming in absurdly close for
    /// two nearby points — the base map itself (native Apple Maps) has no
    /// zoom ceiling of its own to respect.
    func setCenter(_ coordinate: CLLocationCoordinate2D, zoomLevel: Double, animated: Bool, maxZoom: Double = 18) {
        let clamped = min(max(zoomLevel, 2), maxZoom)
        let longitudeDelta = 360 * (zoomReferenceWidth / 256) / pow(2, clamped)
        // Latitude degrees cover less ground away from the equator; without
        // the cosine the vertical span would be too wide this far north.
        let latitudeDelta = longitudeDelta * cos(coordinate.latitude * .pi / 180)

        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: min(max(latitudeDelta, 0.0001), 180),
                longitudeDelta: min(max(longitudeDelta, 0.0001), 360)
            )
        )
        setRegion(regionThatFits(region), animated: animated)
    }

    func fit(_ coordinates: [CLLocationCoordinate2D], maxZoom: Double, padding: CGFloat = 60, animated: Bool = true) {
        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1 {
            setCenter(coordinates[0], zoomLevel: maxZoom, animated: animated, maxZoom: maxZoom)
            return
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        guard !rect.isNull else { return }

        setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding),
            animated: animated
        )

        // `setVisibleMapRect` happily zooms to street level for two adjacent
        // points; the cap keeps the surroundings in frame.
        if zoomLevel > maxZoom {
            setCenter(region.center, zoomLevel: maxZoom, animated: animated, maxZoom: maxZoom)
        }
    }
}
