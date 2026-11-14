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
    /// Immediate move, no animation.
    case jump(CLLocationCoordinate2D, zoom: Double)
    /// Frame all points, never zooming in past `maxZoom`.
    case fit([CLLocationCoordinate2D], maxZoom: Double)
    /// Move, never zooming out from where the map already is.
    case flyAtLeast(CLLocationCoordinate2D, minZoom: Double)

    static func == (lhs: MapCommand, rhs: MapCommand) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}

/// The SwiftUI side's handle on the map: one pending camera move, the follow
/// state the controls show, and direct calls into the map for the things
/// that run every frame (the timeline) and must not go through a re-render.
@MainActor
final class MapCameraController: ObservableObject {
    @Published private(set) var generation = 0
    /// The rider dragged the map while following: it no longer chases the bus.
    @Published private(set) var followPaused = false

    private(set) var pending: MapCommand?
    private(set) var zoom: Double = 13
    weak var coordinator: TransitMapRepresentable.Coordinator?

    func send(_ command: MapCommand) {
        pending = command
        generation &+= 1
    }

    func consume() -> MapCommand? {
        defer { pending = nil }
        return pending
    }

    func updateZoom(_ value: Double) {
        zoom = value
    }

    func setFollowPaused(_ paused: Bool) {
        guard followPaused != paused else { return }
        followPaused = paused
    }

    /// „Busz középre”.
    func resumeFollow() {
        setFollowPaused(false)
        coordinator?.resumeFollow()
    }

    func zoom(by delta: Double) {
        coordinator?.zoom(by: delta)
    }

    /// Draws the timeline at `t`; returns whether data was there and how many vehicles.
    func renderHistory(_ t: Double, frames: MapHistoryFrames, options: MapHistoryRenderOptions) -> MapHistoryRenderResult {
        coordinator?.renderHistory(t, frames: frames, options: options) ?? MapHistoryRenderResult(ready: false, visible: 0)
    }

    func historySample(_ id: String) -> (sample: MapHistorySampler.Sample?, route: String?) {
        coordinator?.historySample(id) ?? (nil, nil)
    }

    func clearHistory() {
        coordinator?.clearHistory()
    }
}

struct MapHistoryRenderOptions {
    let routeByShort: [String: Route]
    let isVisible: (String, String?) -> Bool
    let isTracked: (String) -> Bool
    let showIds: Bool
}

struct MapHistoryRenderResult: Equatable {
    let ready: Bool
    let visible: Int
}

extension MKMapView {

    private var zoomReferenceWidth: CGFloat {
        bounds.width > 1 ? bounds.width : 390
    }

    /// Leaflet-style zoom levels, so the ported logic keeps its numbers.
    var zoomLevel: Double {
        log2(360 * (zoomReferenceWidth / 256) / region.span.longitudeDelta)
    }

    func setCenter(_ coordinate: CLLocationCoordinate2D, zoomLevel: Double, animated: Bool, maxZoom: Double = 19) {
        let clamped = min(max(zoomLevel, 2), maxZoom)
        let longitudeDelta = 360 * (zoomReferenceWidth / 256) / pow(2, clamped)
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
        setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding), animated: animated)
        if zoomLevel > maxZoom {
            setCenter(region.center, zoomLevel: maxZoom, animated: animated, maxZoom: maxZoom)
        }
    }
}
