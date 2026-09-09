//
//  TransitMapRepresentable.swift
//  MVK++ Phone App
//

import MapKit
import SwiftUI

/// The map itself. Wraps `MKMapView` rather than SwiftUI's `Map` for two
/// reasons the ported design depends on: custom raster tiles (SwiftUI has no
/// `MKTileOverlay` equivalent, and the base-map picker is a shipped feature),
/// and annotation-view reuse for a thousand-odd stops plus a live fleet.
struct TransitMapRepresentable: UIViewRepresentable {

    let stops: [Stop]
    let routes: [String: Route]
    let vehicles: [LiveVehicle]
    let filters: FilterState
    let tileLayer: TileLayerOption
    let selectedStopId: String?
    let monitoredStopIds: [String]
    let focusTripId: String?
    /// Path of the trip being followed, refetched by the screen every few
    /// seconds while focus is active.
    let focusPath: TripPathResponse?
    let routeShapes: [String: [[CLLocationCoordinate2D]]]
    let showsUserLocation: Bool

    @ObservedObject var camera: MapCameraController

    var onSelectStop: (String) -> Void
    var onSelectVehicle: (VehicleAnnotation) -> Void
    /// Fired the moment the rider pans or zooms, so automatic recentring can
    /// get out of the way — nothing is more annoying than a map that snaps
    /// back while you are looking at something.
    var onUserMovedMap: () -> Void

    // MARK: - Lifecycle

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        map.isRotateEnabled = false
        map.isPitchEnabled = false

        // Observe-only recognizers: they never claim the touch, they just tell
        // us the rider has taken the wheel.
        for recognizer in [
            UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleUserGesture(_:))),
            UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleUserGesture(_:))),
        ] as [UIGestureRecognizer] {
            recognizer.delegate = context.coordinator
            recognizer.cancelsTouchesInView = false
            map.addGestureRecognizer(recognizer)
        }

        map.register(StopAnnotationView.self, forAnnotationViewWithReuseIdentifier: StopAnnotationView.reuseIdentifier)
        map.register(VehicleAnnotationView.self, forAnnotationViewWithReuseIdentifier: VehicleAnnotationView.reuseIdentifier)

        // Miskolc city centre is the fallback when nothing was saved.
        let saved = ViewStateStore.initialMapView()
        map.setCenter(
            CLLocationCoordinate2D(
                latitude: saved?.lat ?? 48.104,
                longitude: saved?.lon ?? 20.79
            ),
            zoomLevel: saved?.zoom ?? 13,
            animated: false
        )

        context.coordinator.applyTileLayer(tileLayer, to: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        coordinator.applyTileLayer(tileLayer, to: map)
        coordinator.applyStops(stops, filters: filters, selectedStopId: selectedStopId,
                               monitoredStopIds: monitoredStopIds, focusTripId: focusTripId, to: map)
        coordinator.applyVehicles(visibleVehicles(), filters: filters, focusTripId: focusTripId, to: map)
        coordinator.applyRouteShapes(routeShapes, filters: filters, routes: routes, to: map)
        coordinator.applyFocusPath(focusPath, to: map)

        if map.showsUserLocation != showsUserLocation {
            map.showsUserLocation = showsUserLocation
        }

        if let command = camera.consume() {
            coordinator.run(command, on: map)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Filtering

    private func visibleVehicles() -> [LiveVehicle] {
        VehicleFilter.apply(
            vehicles: vehicles,
            filters: filters,
            routes: routes,
            position: userPosition
        )
    }

    /// Set by the screen so the near-me radius can be applied here.
    var userPosition: GeoPosition?

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TransitMapRepresentable

        private var baseOverlay: MapTileOverlay?
        private var labelOverlay: MapTileOverlay?
        private var currentTileLayerId: String?
        /// MapKit owns these; we only need them to say "repaint here" when a
        /// tile turns up after the draw pass that asked for it.
        private weak var baseRenderer: MKTileOverlayRenderer?
        private weak var labelRenderer: MKTileOverlayRenderer?
        /// Late tiles arrive in bursts of dozens. Their rects are unioned and
        /// flushed on a short timer, so a screenful of them costs one
        /// invalidation instead of forty.
        private var repaintScheduled = false
        /// Both debounced: `regionDidChange` fires repeatedly through a pinch,
        /// and neither a `UserDefaults` write nor a prefetch sweep belongs in
        /// that path.
        private var persistWork: DispatchWorkItem?
        private var prefetchWork: DispatchWorkItem?
        private var isGesturing = false

        private var stopAnnotations: [String: StopAnnotation] = [:]
        private var stopSignature = ""
        private var vehicleAnnotations: [String: VehicleAnnotation] = [:]
        private var shapeOverlays: [RouteOverlay] = []
        private var shapeSignature = ""
        private var focusOverlays: [RouteOverlay] = []
        private var focusVehicle: VehicleAnnotation?
        private var focusSignature = ""

        init(parent: TransitMapRepresentable) {
            self.parent = parent
        }

        // MARK: User gestures

        @objc func handleUserGesture(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .began:
                isGesturing = true
                let handler = parent.onUserMovedMap
                MainActor.assumeIsolated { handler() }
            case .ended, .cancelled, .failed:
                isGesturing = false
                // The gesture is over, so a correction can no longer fight it.
                clampZoomIfNeeded(on: recognizer.view as? MKMapView)
            default:
                break
            }
        }

        /// Brings the camera back to the last zoom the tile source actually
        /// has, once the rider's fingers are off.
        ///
        /// This deliberately replaces `setCameraZoomRange`. That clamps what
        /// the *camera* reports while leaving the renderer working from the
        /// zoom the pinch asked for, and the two disagreeing is what left the
        /// map as an empty tile grid: MapKit asked for tiles at the capped
        /// level, was handed every one of them, and drew them at a scale where
        /// they covered nothing. Letting the pinch overshoot and settling
        /// afterwards keeps the camera and the renderer talking about the same
        /// map.
        private func clampZoomIfNeeded(on map: MKMapView?) {
            guard let map else { return }
            let ceiling = Double(parent.tileLayer.maxNativeZoom)
            guard map.zoomLevel > ceiling + 0.1 else { return }
            map.setCenter(map.region.center, zoomLevel: ceiling, animated: true, maxZoom: ceiling)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: Tiles

        func applyTileLayer(_ option: TileLayerOption, to map: MKMapView) {
            guard currentTileLayerId != option.id else { return }
            currentTileLayerId = option.id

            if let baseOverlay { map.removeOverlay(baseOverlay) }
            if let labelOverlay { map.removeOverlay(labelOverlay) }
            labelOverlay = nil

            baseRenderer = nil
            labelRenderer = nil

            let base = MapTileOverlay(option: option)
            base.onTileReady = { [weak self] rect in
                self?.scheduleRepaint(rect, labels: false)
            }
            map.insertOverlay(base, at: 0, level: .aboveLabels)
            baseOverlay = base

            if option.labelsUrl != nil {
                let labels = MapTileOverlay(option: option, labels: true)
                labels.canReplaceMapContent = false
                labels.onTileReady = { [weak self] rect in
                    self?.scheduleRepaint(rect, labels: true)
                }
                map.insertOverlay(labels, at: 1, level: .aboveLabels)
                labelOverlay = labels
            }
        }

        /// Notes that a real tile has landed and makes sure the layer is
        /// repainted once the burst is over.
        ///
        /// `reloadData` rather than `setNeedsDisplay(_:)`, because the slot
        /// very likely holds a blown-up stand-in and the renderer would
        /// happily redraw that same stand-in. Only a reload asks for the tile
        /// again — and by the time this fires every tile on screen is in
        /// memory, so the reload is answered synchronously and nothing
        /// blanks. The delay is what makes it one reload per zoom rather than
        /// one per tile.
        private func scheduleRepaint(_ rect: MKMapRect, labels: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, !repaintScheduled else { return }
                repaintScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.flushRepaint()
                }
            }
        }

        private func flushRepaint() {
            repaintScheduled = false
            baseRenderer?.reloadData()
            labelRenderer?.reloadData()
        }

        // MARK: Stops

        func applyStops(
            _ stops: [Stop],
            filters: FilterState,
            selectedStopId: String?,
            monitoredStopIds: [String],
            focusTripId: String?,
            to map: MKMapView
        ) {
            // While a trip is being followed the stop layer is hidden, exactly
            // as on the web — the followed path is the whole story then.
            let hidden = !filters.stops || focusTripId != nil
            let watched = Set(monitoredStopIds)
            let visible = hidden
                ? []
                : (filters.onlyWatched ? stops.filter { watched.contains($0.id) } : stops)

            let signature = "\(hidden)|\(filters.onlyWatched)|\(stops.count)|\(watched.sorted().joined(separator: ","))|\(selectedStopId ?? "")"
            guard signature != stopSignature else { return }
            stopSignature = signature

            map.removeAnnotations(Array(stopAnnotations.values))
            stopAnnotations = [:]
            guard !visible.isEmpty else { return }

            let created = visible.map {
                StopAnnotation(
                    stop: $0,
                    isWatched: watched.contains($0.id),
                    isSelected: selectedStopId == $0.id
                )
            }
            created.forEach { stopAnnotations[$0.stopId] = $0 }
            map.addAnnotations(created)
        }

        // MARK: Vehicles

        /// Vehicles move every few seconds, so annotations are updated in
        /// place: only genuinely new or changed ones are added, and the rest
        /// just get a new coordinate. Replacing all of them each tick would
        /// make the fleet flicker.
        func applyVehicles(
            _ vehicles: [LiveVehicle],
            filters: FilterState,
            focusTripId: String?,
            to map: MKMapView
        ) {
            guard focusTripId == nil else {
                if !vehicleAnnotations.isEmpty {
                    map.removeAnnotations(Array(vehicleAnnotations.values))
                    vehicleAnnotations = [:]
                }
                return
            }

            let watchSet = Set(filters.watch.map { $0.lowercased() })
            let query = filters.vq.trimmingCharacters(in: .whitespaces).lowercased()

            var next: [String: VehicleAnnotation] = [:]
            var toAdd: [VehicleAnnotation] = []
            var toRemove: [VehicleAnnotation] = []

            for vehicle in vehicles {
                guard let coordinate = vehicle.coordinate else { continue }
                // The feed can report one vehicle twice — the same bus handed
                // over between two trips. Keying off `next` as well as the
                // live map means the second copy updates the first instead of
                // adding an annotation nothing is tracking, which is how a
                // marker used to end up on the map with no way to remove it.
                guard next[vehicle.id] == nil else { continue }

                let tracked = watchSet.contains(vehicle.id.lowercased())
                    || (!query.isEmpty && vehicle.id.lowercased().contains(query))

                let candidate = VehicleAnnotation(
                    vehicle: vehicle,
                    tracked: tracked,
                    showLabel: filters.labels
                )

                if let existing = vehicleAnnotations[vehicle.id] {
                    // Update in place. Removing and re-adding the annotation
                    // made markers blink out for a frame on every poll, which
                    // read as vehicles randomly vanishing from the map.
                    if existing.renderKey != candidate.renderKey {
                        existing.absorb(candidate)
                        map.view(for: existing)?.annotation = existing
                    }
                    if existing.coordinate.latitude != coordinate.latitude
                        || existing.coordinate.longitude != coordinate.longitude {
                        // `coordinate` is KVO-observed by MapKit, so this both
                        // moves the marker and keeps MapKit's own index in
                        // step; the animation block makes it glide.
                        UIView.animate(withDuration: Theme.Motion.normal) {
                            existing.coordinate = coordinate
                        }
                    }
                    next[vehicle.id] = existing
                } else {
                    next[vehicle.id] = candidate
                    toAdd.append(candidate)
                }
            }

            for (id, annotation) in vehicleAnnotations where next[id] == nil {
                toRemove.append(annotation)
            }

            // Anything on the map this coordinator is no longer tracking is a
            // leak by definition. Sweeping here means a stray marker survives
            // at most one poll instead of until the app is killed.
            let tracked = Set(next.values.map(ObjectIdentifier.init))
            for annotation in map.annotations {
                guard let vehicle = annotation as? VehicleAnnotation,
                      vehicle !== focusVehicle,
                      !tracked.contains(ObjectIdentifier(vehicle))
                else { continue }
                toRemove.append(vehicle)
            }

            if !toRemove.isEmpty { map.removeAnnotations(toRemove) }
            if !toAdd.isEmpty { map.addAnnotations(toAdd) }
            vehicleAnnotations = next
        }

        // MARK: Route shapes

        func applyRouteShapes(
            _ shapes: [String: [[CLLocationCoordinate2D]]],
            filters: FilterState,
            routes: [String: Route],
            to map: MKMapView
        ) {
            let active = (filters.shape && !filters.routes.isEmpty) ? filters.routes : []
            let signature = active.sorted().joined(separator: ",") + "|" + active.compactMap { shapes[$0] != nil ? $0 : nil }.joined(separator: ",")
            guard signature != shapeSignature else { return }
            shapeSignature = signature

            map.removeOverlays(shapeOverlays)
            shapeOverlays = []
            guard !active.isEmpty else { return }

            var created: [RouteOverlay] = []
            for routeId in active {
                guard let lines = shapes[routeId] else { continue }
                let colorHex = routes[routeId]?.color ?? "1FB574"
                for line in lines where line.count > 1 {
                    let halo = RouteOverlay(coordinates: line, count: line.count)
                    halo.isHalo = true
                    halo.colorHex = colorHex
                    let stroke = RouteOverlay(coordinates: line, count: line.count)
                    stroke.colorHex = colorHex
                    created.append(halo)
                    created.append(stroke)
                }
            }
            shapeOverlays = created
            // Above the tiles, below the annotations.
            map.addOverlays(created, level: .aboveLabels)
        }

        // MARK: Followed trip

        func applyFocusPath(_ path: TripPathResponse?, to map: MKMapView) {
            let signature = path.map { "\($0.trip)|\($0.shape.count)|\($0.vehicle?.id ?? "")|\($0.vehicle?.lat ?? 0)|\($0.vehicle?.lon ?? 0)" } ?? ""
            guard signature != focusSignature else { return }
            focusSignature = signature

            map.removeOverlays(focusOverlays)
            focusOverlays = []
            if let focusVehicle {
                map.removeAnnotation(focusVehicle)
                self.focusVehicle = nil
            }

            guard let path else { return }

            let coordinates = path.shape.compactMap { point -> CLLocationCoordinate2D? in
                guard point.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
            }

            if coordinates.count > 1 {
                let halo = RouteOverlay(coordinates: coordinates, count: coordinates.count)
                halo.isHalo = true
                halo.isFocus = true
                halo.colorHex = path.color
                let stroke = RouteOverlay(coordinates: coordinates, count: coordinates.count)
                stroke.isFocus = true
                stroke.colorHex = path.color
                focusOverlays = [halo, stroke]
                map.addOverlays(focusOverlays, level: .aboveLabels)
            }

            if let vehicle = path.vehicle {
                let annotation = VehicleAnnotation(tripPath: path, vehicle: vehicle)
                focusVehicle = annotation
                map.addAnnotation(annotation)
            }
        }

        // MARK: Camera

        func run(_ command: MapCommand, on map: MKMapView) {
            let ceiling = Double(parent.tileLayer.maxNativeZoom)
            switch command {
            case .fly(let coordinate, let zoom):
                map.setCenter(coordinate, zoomLevel: zoom, animated: true, maxZoom: ceiling)
            case .jump(let coordinate, let zoom):
                map.setCenter(coordinate, zoomLevel: zoom, animated: false, maxZoom: ceiling)
            case .fit(let coordinates, let maxZoom):
                map.fit(coordinates, maxZoom: min(maxZoom, ceiling))
            case .flyAtLeast(let coordinate, let minZoom):
                map.setCenter(coordinate, zoomLevel: max(map.zoomLevel, minZoom), animated: true, maxZoom: ceiling)
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                if let mapTile = tile as? MapTileOverlay {
                    if mapTile === labelOverlay {
                        labelRenderer = renderer
                    } else {
                        baseRenderer = renderer
                    }
                }
                return renderer
            }

            if let route = overlay as? RouteOverlay {
                let renderer = MKPolylineRenderer(polyline: route)
                renderer.lineCap = .round
                renderer.lineJoin = .round
                if route.isHalo {
                    renderer.strokeColor = UIColor(Theme.background).withAlphaComponent(route.isFocus ? 0.6 : 0.55)
                    renderer.lineWidth = route.isFocus ? 8 : 6
                } else {
                    renderer.strokeColor = UIColor(Theme.hex(route.colorHex)).withAlphaComponent(0.95)
                    renderer.lineWidth = route.isFocus ? 4 : 3
                }
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if annotation is StopAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: StopAnnotationView.reuseIdentifier,
                    for: annotation
                )
                view.annotation = annotation
                return view
            }

            if annotation is VehicleAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: VehicleAnnotationView.reuseIdentifier,
                    for: annotation
                )
                view.annotation = annotation
                return view
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            // Selection is a one-shot signal here; the app drives its own
            // sheets, so the pin must not stay latched.
            mapView.deselectAnnotation(annotation, animated: false)

            if let stop = annotation as? StopAnnotation {
                parent.onSelectStop(stop.stopId)
            } else if let vehicle = annotation as? VehicleAnnotation {
                parent.onSelectVehicle(vehicle)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            let zoom = mapView.zoomLevel

            // Nothing corrects the region here. Re-setting it from inside this
            // callback fires the callback again, and doing that while a pinch
            // is still running fought the gesture frame by frame — that was
            // the shaking. Overshooting the tile source is settled once, when
            // the fingers come off, in `clampZoomIfNeeded`.
            MainActor.assumeIsolated { self.parent.camera.updateZoom(zoom) }
            schedulePersist(center: region.center, zoom: zoom)
            schedulePrefetch(region: region, zoom: zoom)
        }

        // MARK: Debounced side effects

        private func schedulePersist(center: CLLocationCoordinate2D, zoom: Double) {
            persistWork?.cancel()
            let work = DispatchWorkItem {
                ViewStateStore.save(
                    ViewStateStore.MapView(lat: center.latitude, lon: center.longitude, zoom: zoom)
                )
            }
            persistWork = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        /// Warms the next zoom level in, for the ground currently on screen.
        ///
        /// A pinch asks for a whole new level of tiles at once, and that
        /// burst is exactly when the map used to go to pieces. Fetching them
        /// while the rider is still looking at the current level turns the
        /// zoom into a cache read.
        private func schedulePrefetch(region: MKCoordinateRegion, zoom: Double) {
            prefetchWork?.cancel()
            guard let overlay = baseOverlay else { return }

            let box = TileBoundingBox(
                minLat: region.center.latitude - region.span.latitudeDelta / 2,
                minLon: region.center.longitude - region.span.longitudeDelta / 2,
                maxLat: region.center.latitude + region.span.latitudeDelta / 2,
                maxLon: region.center.longitude + region.span.longitudeDelta / 2
            )
            let current = Int(zoom.rounded()) + MapTileOverlay.zoomOffset
            // Both directions: a pinch out is just as likely as a pinch in,
            // and the level the rider zooms *away* to is the one that used to
            // arrive blank.
            let levels = [current + 1, current - 1]
                .filter { $0 >= overlay.minimumZ && $0 <= overlay.maximumZ }

            let work = DispatchWorkItem {
                for level in levels {
                    let tiles = TileMath.tiles(in: box, z: level)
                    // A screenful at the next level in is four times the
                    // current one; beyond that the rider has already moved on.
                    guard tiles.count <= Self.prefetchLimit else { continue }
                    for tile in tiles {
                        overlay.warm(tile) { _ in }
                    }
                }
            }
            prefetchWork = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.45, execute: work)
        }

        private static let prefetchLimit = 64
    }
}
