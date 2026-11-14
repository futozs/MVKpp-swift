//
//  TransitMapRepresentable.swift
//  MVK++ Phone App
//
//  The map itself — the web's `TransitMap` layers on an `MKMapView`: stops,
//  live vehicles moved every 250 ms along their expected path, the followed
//  trip with its bus, live congestion, the rider's position, the timeline's
//  replayed vehicles, and the 3D city with a chase camera behind the bus.
//
//  The base map is Apple's own renderer (`MKMapConfiguration`) rather than
//  raster tiles: panning and zooming are smooth by construction, at the cost
//  of an exact match with the web's colour-filtered OSM layers.
//

import MapKit
import SwiftUI

struct TransitMapRepresentable: UIViewRepresentable {

    let stops: [Stop]
    let routes: [String: Route]
    /// Every live vehicle (the followed one is found here).
    let vehicles: [LiveVehicle]
    /// The filtered, visible ones.
    let visibleVehicles: [LiveVehicle]
    let filters: FilterState
    let tileLayer: TileLayerOption
    let selectedStopId: String?
    let monitoredStopIds: [String]
    let focusTripId: String?
    let focusVehicleId: String?
    let focusPath: TripPathResponse?
    let routeShapes: [String: [[CLLocationCoordinate2D]]]
    let traffic: [MapTrafficSegment]
    let userPosition: GeoPosition?
    /// The phone's live fix while riding: the ridden bus follows it.
    let ridePosition: GeoPosition?
    let riddenVehicleId: String?
    let is3D: Bool
    let historyOn: Bool
    /// The map tab is on screen; the motion tick idles otherwise.
    var isActive = true
    /// Height of the panel covering the bottom of the map (focus card, ride).
    let coverBottom: CGFloat

    @ObservedObject var camera: MapCameraController

    var onSelectStop: (String) -> Void
    var onSelectVehicle: (String) -> Void
    var onSelectHistoryVehicle: (String) -> Void
    var onSelectTraffic: (MapTrafficSegment) -> Void
    var onTapMap: () -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.layoutMargins = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 64)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        for recognizer in [pan, pinch, tap] as [UIGestureRecognizer] {
            recognizer.delegate = context.coordinator
            recognizer.cancelsTouchesInView = false
            map.addGestureRecognizer(recognizer)
        }

        map.register(StopAnnotationView.self, forAnnotationViewWithReuseIdentifier: StopAnnotationView.reuseIdentifier)
        map.register(VehicleAnnotationView.self, forAnnotationViewWithReuseIdentifier: VehicleAnnotationView.reuseIdentifier)
        map.register(UserDotAnnotationView.self, forAnnotationViewWithReuseIdentifier: UserDotAnnotationView.reuseIdentifier)

        let saved = ViewStateStore.initialMapView()
        map.setCenter(
            CLLocationCoordinate2D(latitude: saved?.lat ?? 48.104, longitude: saved?.lon ?? 20.79),
            zoomLevel: saved?.zoom ?? 13,
            animated: false
        )
        context.coordinator.attach(map)
        context.coordinator.applyTileLayer(tileLayer, is3D: is3D, to: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        camera.coordinator = coordinator

        coordinator.applyTileLayer(tileLayer, is3D: is3D, to: map)
        coordinator.applyStops(to: map)
        coordinator.applyVehicles(to: map)
        coordinator.applyFocus(to: map)
        coordinator.applyFocusPath(focusPath, to: map)
        coordinator.applyRouteShapes(to: map)
        coordinator.applyTraffic(to: map)
        coordinator.applyUserPosition(userPosition, to: map)

        if let command = camera.consume() {
            coordinator.run(command, on: map)
        }
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// The id under the tile: a train's number, otherwise the plate / fleet number.
    static func vehicleIdText(id: String, plate: String?, trainNo: String?, trainName: String?, mode: TransitMode?) -> String? {
        mode == .rail ? (trainNo ?? trainName) : TransitIds.displayVehicleId(id, plate: plate)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TransitMapRepresentable
        private weak var map: MKMapView?

        private var currentTileKey: String?
        private var persistWork: DispatchWorkItem?

        // Stops
        private var stopAnnotations: [String: StopAnnotation] = [:]
        private var stopSignature = ""
        private var stopZoom: Double = 13
        private var stopBounds: MKMapRect?

        // Live vehicles
        private struct LiveEntry {
            let annotation: VehicleAnnotation
            var vehicle: LiveVehicle
            var shown: ShownMotion?
        }
        private var live: [String: LiveEntry] = [:]

        // The followed vehicle
        private struct FocusEntry {
            let annotation: VehicleAnnotation
            var id: String?
            var motion: LiveMotion?
            var shown: ShownMotion?
            var raw: CLLocationCoordinate2D
            var bearing: Double?
        }
        private var focus: FocusEntry?
        private var focusKey = ""
        private var focusOverlays: [RouteOverlay] = []
        private var focusSignature = ""

        // Follow
        private var followPaused = false
        private var followCentered = false
        private var zooming = false
        private var holdUntil = Date.distantPast
        private var chaseHeading: Double?
        private var chaseLead: Double?
        private var focusLine: ShapeLine?
        private var focusAlong: Double?
        private var lastHeadingPoint: CLLocationCoordinate2D?

        // Layers
        private var shapeOverlays: [RouteOverlay] = []
        private var shapeSignature = ""
        private var trafficOverlays: [TrafficOverlay] = []
        private var trafficSignature = ""
        private var userDot: UserDotAnnotation?
        private var accuracy: AccuracyCircle?
        private var accuracySignature = ""

        // Timeline
        private struct HistoryState {
            let annotation: VehicleAnnotation
            var iconKey: String
            var shown: Bool
            var hint: Int
            var windowStart: Double
            var frame: Int
            var route: String?
            var sample: MapHistorySampler.Sample?
        }
        private var history: [String: HistoryState] = [:]
        private var historyFrame = 0
        private var historyStale = false
        private var lastHistory = MapHistoryRenderResult(ready: false, visible: 0)

        private var timer: Timer?
        private static let tick: TimeInterval = 0.25
        private static let regionalMotionZoom: Double = 11
        private static let coachStopsZoom: Double = 14
        private static let focusZoom: Double = 15
        private static let glidePx: CGFloat = 40
        private static let recenterHold: TimeInterval = 0.45

        init(parent: TransitMapRepresentable) {
            self.parent = parent
        }

        func attach(_ map: MKMapView) {
            self.map = map
            parent.camera.coordinator = self
            timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tickMotion() }
            }
        }

        func detach() {
            timer?.invalidate()
            timer = nil
        }

        // MARK: Gestures

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began, parent.focusTripId != nil else { return }
            followPaused = true
            parent.camera.setFollowPaused(true)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began: zooming = true
            case .ended, .cancelled, .failed: zooming = false
            default: break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let map, recognizer.state == .ended else { return }
            let point = recognizer.location(in: map)
            if let hit = map.hitTest(point, with: nil), hit is MKAnnotationView || hit.superview is MKAnnotationView {
                return
            }
            if let segment = trafficSegment(at: point, in: map) {
                parent.onSelectTraffic(segment)
            } else {
                parent.onTapMap()
            }
        }

        nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        private func trafficSegment(at point: CGPoint, in map: MKMapView) -> MapTrafficSegment? {
            var best: (MapTrafficSegment, CGFloat)?
            for overlay in trafficOverlays where !overlay.isHalo {
                guard let segment = overlay.segment else { continue }
                let points = (0..<overlay.pointCount).map { map.convert(overlay.points()[$0].coordinate, toPointTo: map) }
                for i in 0..<max(0, points.count - 1) {
                    let d = Self.distance(point, points[i], points[i + 1])
                    if d <= 16, d < (best?.1 ?? .infinity) { best = (segment, d) }
                }
            }
            return best?.0
        }

        private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }

        // MARK: Base map

        func applyTileLayer(_ option: TileLayerOption, is3D: Bool, to map: MKMapView) {
            let key = "\(option.id)|\(is3D)"
            guard currentTileKey != key else { return }
            let wasSet = currentTileKey != nil
            let was3D = currentTileKey?.hasSuffix("|true") == true
            currentTileKey = key

            let elevation: MKMapConfiguration.ElevationStyle = is3D || option.style == .standardTerrain ? .realistic : .flat
            switch option.style {
            case .standard, .standardTerrain:
                map.overrideUserInterfaceStyle = .light
                map.preferredConfiguration = standard(elevation, .default)
            case .standardDark:
                map.overrideUserInterfaceStyle = .dark
                map.preferredConfiguration = standard(elevation, .default)
            case .standardMuted:
                map.overrideUserInterfaceStyle = .light
                map.preferredConfiguration = standard(elevation, .muted)
            case .hybrid:
                map.overrideUserInterfaceStyle = .unspecified
                let configuration = MKHybridMapConfiguration(elevationStyle: .realistic)
                configuration.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = configuration
            }
            map.isPitchEnabled = is3D
            map.isRotateEnabled = is3D
            map.showsBuildings = true

            guard wasSet, was3D != is3D else { return }
            followCentered = false
            followPaused = false
            parent.camera.setFollowPaused(false)
            chaseHeading = nil
            chaseLead = nil
            if is3D {
                guard parent.focusTripId == nil else { return }
                let camera = map.camera.copy() as? MKMapCamera ?? MKMapCamera()
                camera.pitch = 55
                camera.heading = 342
                camera.centerCoordinateDistance = min(camera.centerCoordinateDistance, 1800)
                map.setCamera(camera, animated: true)
            } else {
                let camera = map.camera.copy() as? MKMapCamera ?? MKMapCamera()
                camera.pitch = 0
                camera.heading = 0
                map.setCamera(camera, animated: true)
            }
        }

        private func standard(_ elevation: MKMapConfiguration.ElevationStyle, _ emphasis: MKStandardMapConfiguration.EmphasisStyle) -> MKStandardMapConfiguration {
            let configuration = MKStandardMapConfiguration(elevationStyle: elevation, emphasisStyle: emphasis)
            configuration.pointOfInterestFilter = .excludingAll
            configuration.showsTraffic = false
            return configuration
        }

        // MARK: Stops

        func applyStops(to map: MKMapView) {
            let p = parent
            let filters = p.filters
            let hidden = !filters.stops || p.focusTripId != nil
            let watched = Set(p.monitoredStopIds)
            let close = stopZoom >= Self.coachStopsZoom
            let boundsKey = close ? stopBounds.map { "\(Int($0.origin.x / 2000)),\(Int($0.origin.y / 2000)),\(Int($0.size.width / 2000))" } ?? "" : ""
            let signature = "\(hidden)|\(filters.onlyWatched)|\(p.stops.count)|\(watched.sorted().joined(separator: ","))|\(p.selectedStopId ?? "")|\(close)|\(boundsKey)"
            guard signature != stopSignature else { return }
            stopSignature = signature

            var wanted: [String: StopAnnotation] = [:]
            if !hidden {
                let ids = Set(p.stops.map(\.id))
                let source = filters.onlyWatched ? p.stops.filter { watched.contains($0.id) } : p.stops
                for s in source {
                    if let parentId = s.parent, !parentId.isEmpty, ids.contains(parentId) { continue }
                    let coach = (s.feed ?? TransitFeed.of(id: s.id).rawValue) == "coach"
                    if coach, s.station != true, !watched.contains(s.id), p.selectedStopId != s.id {
                        guard close else { continue }
                        if let bounds = stopBounds, !bounds.contains(MKMapPoint(CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon))) { continue }
                    }
                    let isWatched = watched.contains(s.id)
                    let isSelected = p.selectedStopId == s.id
                    if let existing = stopAnnotations[s.id], existing.isWatched == isWatched, existing.isSelected == isSelected, existing.isClose == close {
                        wanted[s.id] = existing
                    } else {
                        wanted[s.id] = StopAnnotation(stop: s, isWatched: isWatched, isSelected: isSelected, isClose: close)
                    }
                }
            }
            let remove = stopAnnotations.compactMap { id, a in wanted[id] === a ? nil : a }
            let add = wanted.compactMap { id, a in stopAnnotations[id] === a ? nil : a }
            if !remove.isEmpty { map.removeAnnotations(remove) }
            if !add.isEmpty { map.addAnnotations(add) }
            stopAnnotations = wanted
        }

        // MARK: Live vehicles

        private func isFocused(_ v: LiveVehicle) -> Bool {
            guard let tripId = parent.focusTripId else { return false }
            if let vehicleId = parent.focusVehicleId { return v.id == vehicleId }
            return v.tripId == tripId
        }

        func applyVehicles(to map: MKMapView) {
            let p = parent
            if p.historyOn || (p.focusTripId != nil && !p.filters.others) {
                if !live.isEmpty {
                    map.removeAnnotations(live.values.map(\.annotation))
                    live = [:]
                }
                return
            }
            let dim = p.focusTripId != nil
            let watchSet = Set(p.filters.watch.map { $0.lowercased() })
            let query = p.filters.vq.trimmingCharacters(in: .whitespaces).lowercased()
            var seen = Set<String>()
            var add: [VehicleAnnotation] = []

            for v in p.visibleVehicles where !isFocused(v) {
                guard let coordinate = v.coordinate, !seen.contains(v.id) else { continue }
                seen.insert(v.id)
                let lower = v.id.lowercased()
                let tracked = watchSet.contains(lower) || (!query.isEmpty && lower.contains(query))
                let mode = v.transitMode(routes: p.routes)
                let label = p.filters.labels || tracked
                    ? TransitMapRepresentable.vehicleIdText(id: v.id, plate: v.plate, trainNo: v.trainNo, trainName: v.trainName, mode: mode)
                    : nil
                let candidate = VehicleAnnotation(
                    vehicleId: v.id, tripId: v.tripId, routeShort: v.routeShort, routeColor: v.routeColor.isEmpty ? "1FB574" : v.routeColor,
                    routeText: v.routeText.isEmpty ? "FFFFFF" : v.routeText, headsign: v.headsign, coordinate: coordinate,
                    tracked: tracked, labelText: label, mode: mode, estimated: v.estimated == true, dimmed: dim
                )
                if var entry = live[v.id] {
                    entry.vehicle = v
                    if entry.annotation.renderKey != candidate.renderKey {
                        entry.annotation.absorb(candidate)
                        (map.view(for: entry.annotation) as? VehicleAnnotationView)?.apply()
                    }
                    if v.motion == nil {
                        entry.shown = nil
                        move(entry.annotation, to: coordinate, animated: true)
                    }
                    live[v.id] = entry
                } else {
                    live[v.id] = LiveEntry(annotation: candidate, vehicle: v, shown: nil)
                    add.append(candidate)
                }
            }
            let gone = live.filter { !seen.contains($0.key) }
            if !gone.isEmpty {
                map.removeAnnotations(gone.values.map(\.annotation))
                for id in gone.keys { live[id] = nil }
            }
            if !add.isEmpty { map.addAnnotations(add) }
        }

        private func move(_ annotation: VehicleAnnotation, to coordinate: CLLocationCoordinate2D, animated: Bool) {
            let current = annotation.coordinate
            guard current.latitude != coordinate.latitude || current.longitude != coordinate.longitude else { return }
            if animated {
                UIView.animate(withDuration: Self.tick, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) {
                    annotation.coordinate = coordinate
                }
            } else {
                annotation.coordinate = coordinate
            }
        }

        // MARK: The followed vehicle

        func applyFocus(to map: MKMapView) {
            let p = parent
            let key = "\(p.focusTripId ?? "")|\(p.focusVehicleId ?? "")"
            if key != focusKey {
                focusKey = key
                if let focus { map.removeAnnotation(focus.annotation) }
                focus = nil
                followPaused = false
                followCentered = false
                zooming = false
                chaseHeading = nil
                chaseLead = nil
                p.camera.setFollowPaused(false)
            }
            guard p.focusTripId != nil, !p.historyOn else {
                if let focus { map.removeAnnotation(focus.annotation) }
                focus = nil
                return
            }
            let liveVehicle = p.vehicles.first { isFocused($0) && $0.coordinate != nil }
            let last = p.focusPath?.vehicle
            guard let raw = liveVehicle?.coordinate ?? last.map({ CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }) else { return }

            let route = liveVehicle?.routeShort.isEmpty == false ? liveVehicle?.routeShort ?? "?" : p.focusPath?.route ?? "?"
            let color = liveVehicle?.routeColor.isEmpty == false ? liveVehicle?.routeColor ?? "1FB574" : p.focusPath?.color ?? "1FB574"
            let text = liveVehicle?.routeText.isEmpty == false ? liveVehicle?.routeText ?? "FFFFFF" : p.focusPath?.text ?? "FFFFFF"
            let id = liveVehicle?.id ?? last?.id ?? p.focusVehicleId
            let mode = liveVehicle?.transitMode(routes: p.routes)
            let shownId = id.flatMap {
                TransitMapRepresentable.vehicleIdText(id: $0, plate: liveVehicle?.plate, trainNo: liveVehicle?.trainNo, trainName: liveVehicle?.trainName, mode: mode)
            }
            let candidate = VehicleAnnotation(
                vehicleId: id ?? "focus", tripId: p.focusTripId ?? "", routeShort: route, routeColor: color, routeText: text,
                headsign: liveVehicle?.headsign ?? p.focusPath?.headsign ?? "", coordinate: raw, tracked: true, labelText: shownId,
                mode: mode, estimated: liveVehicle?.estimated == true, dimmed: false, isFocus: true
            )

            if var entry = focus {
                guard let liveVehicle else {
                    entry.motion = nil
                    focus = entry
                    return
                }
                entry.motion = liveVehicle.motion
                entry.raw = raw
                entry.id = id
                entry.bearing = liveVehicle.bearing
                if entry.annotation.renderKey != candidate.renderKey {
                    entry.annotation.absorb(candidate)
                    (map.view(for: entry.annotation) as? VehicleAnnotationView)?.apply()
                }
                if liveVehicle.motion == nil {
                    entry.shown = nil
                    move(entry.annotation, to: raw, animated: true)
                }
                focus = entry
                return
            }
            focus = FocusEntry(annotation: candidate, id: id, motion: liveVehicle?.motion, shown: nil, raw: raw, bearing: liveVehicle?.bearing ?? last?.bearing)
            map.addAnnotation(candidate)
            tickFocus(now: RealtimeClient.shared.serverNow)
        }

        func applyFocusPath(_ path: TripPathResponse?, to map: MKMapView) {
            let signature = path.map { "\($0.trip)|\($0.shape.count)|\($0.color)" } ?? ""
            guard signature != focusSignature else { return }
            focusSignature = signature
            map.removeOverlays(focusOverlays)
            focusOverlays = []
            focusLine = nil
            focusAlong = nil
            guard let path, parent.focusTripId != nil else { return }
            let coordinates = path.shape.compactMap { point -> CLLocationCoordinate2D? in
                point.count >= 2 ? CLLocationCoordinate2D(latitude: point[0], longitude: point[1]) : nil
            }
            guard coordinates.count > 1 else { return }
            var cum: [Double] = [0]
            for i in 1..<coordinates.count {
                cum.append(cum[i - 1] + MapChase.meters(coordinates[i - 1], coordinates[i]))
            }
            focusLine = ShapeLine(id: nil, pts: coordinates.map { [$0.latitude, $0.longitude] }, cum: cum)
            focusAlong = nil
            let halo = RouteOverlay(coordinates: coordinates, count: coordinates.count)
            halo.isHalo = true
            halo.isFocus = true
            halo.colorHex = path.color
            let stroke = RouteOverlay(coordinates: coordinates, count: coordinates.count)
            stroke.isFocus = true
            stroke.colorHex = path.color
            focusOverlays = [halo, stroke]
            map.addOverlays(focusOverlays, level: .aboveLabels)
            if focus == nil, path.vehicle == nil {
                map.fit(coordinates, maxZoom: 16)
            }
        }

        // MARK: Motion tick

        private func tickMotion() {
            guard let map, !parent.historyOn, parent.isActive else { return }
            let now = RealtimeClient.shared.serverNow
            let ridden = parent.riddenVehicleId
            let gps = ridden != nil ? parent.ridePosition : nil
            let view: MKMapRect? = map.zoomLevel >= Self.regionalMotionZoom
                ? map.visibleMapRect.insetBy(dx: -map.visibleMapRect.width * 0.3, dy: -map.visibleMapRect.height * 0.3)
                : nil
            for (id, entry) in live {
                let v = entry.vehicle
                guard let raw = v.coordinate else { continue }
                if TransitIds.isRegional(v.id), v.id != ridden, view.map({ !$0.contains(MKMapPoint(raw)) }) ?? true {
                    live[id]?.shown = nil
                    move(entry.annotation, to: raw, animated: false)
                    continue
                }
                guard let est = LiveMotionEstimator.estimate(v.motion, nowServer: now, shown: entry.shown, onboard: v.id == ridden ? gps : nil) else {
                    move(entry.annotation, to: raw, animated: false)
                    continue
                }
                live[id]?.shown = est.shown
                move(entry.annotation, to: est.coordinate, animated: true)
            }
            tickFocus(now: now)
        }

        private func tickFocus(now: Double) {
            guard var entry = focus else { return }
            let ridden = parent.riddenVehicleId
            let gps = ridden != nil && entry.id == ridden ? parent.ridePosition : nil
            if let est = LiveMotionEstimator.estimate(entry.motion, nowServer: now, shown: entry.shown, onboard: gps) {
                entry.shown = est.shown
                move(entry.annotation, to: est.coordinate, animated: true)
            } else {
                move(entry.annotation, to: entry.raw, animated: true)
            }
            focus = entry
            follow(entry.annotation.coordinate, entry: entry)
        }

        // MARK: Follow

        private func visibleCenterPoint(in map: MKMapView) -> CGPoint {
            let top = map.safeAreaInsets.top
            let cover = min(parent.coverBottom, map.bounds.height * 0.8)
            return CGPoint(x: map.bounds.midX, y: top + (map.bounds.height - cover - top) / 2)
        }

        private func follow(_ position: CLLocationCoordinate2D, entry: FocusEntry) {
            guard let map, !followPaused, !zooming, Date() >= holdUntil else { return }
            if parent.is3D {
                chase(position, entry: entry, in: map)
                return
            }
            let first = !followCentered
            if first {
                followCentered = true
                map.setCenter(position, zoomLevel: max(map.zoomLevel, Self.focusZoom), animated: false)
            }
            let point = map.convert(position, toPointTo: map)
            let target = visibleCenterPoint(in: map)
            let off = CGPoint(x: point.x - target.x, y: point.y - target.y)
            guard abs(off.x) >= 1 || abs(off.y) >= 1 else { return }
            let center = map.convert(CGPoint(x: map.bounds.midX + off.x, y: map.bounds.midY + off.y), toCoordinateFrom: map)
            let camera = map.camera.copy() as? MKMapCamera ?? MKMapCamera()
            camera.centerCoordinate = center
            if !first, hypot(off.x, off.y) > Self.glidePx {
                holdUntil = Date().addingTimeInterval(Self.recenterHold)
                UIView.animate(withDuration: Self.recenterHold - 0.05, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    map.camera = camera
                }
            } else if first {
                map.camera = camera
            } else {
                UIView.animate(withDuration: Self.tick, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) {
                    map.camera = camera
                }
            }
        }

        /// 3D: from behind the bus, looking where it is heading; the bus in the
        /// lower part of the view, the road ahead above it.
        private func chase(_ position: CLLocationCoordinate2D, entry: FocusEntry, in map: MKMapView) {
            let target = headingTarget(position, entry: entry)
            let current = chaseHeading ?? target ?? map.camera.heading
            let heading = target.map { MapChase.approach(current, $0, dt: Self.tick) } ?? current
            chaseHeading = heading
            let first = !followCentered
            followCentered = true
            let distance = first ? 700 : min(max(map.camera.centerCoordinateDistance, 250), 4000)
            var lead = chaseLead ?? distance * 0.15
            if !first {
                let point = map.convert(position, toPointTo: map)
                let top = map.safeAreaInsets.top
                let cover = min(parent.coverBottom, map.bounds.height * 0.8)
                let targetY = top + (map.bounds.height - cover - top) * 0.7
                let below = map.convert(CGPoint(x: point.x, y: point.y + 1), toCoordinateFrom: map)
                let metersPerPx = MapChase.meters(position, below)
                if metersPerPx.isFinite, metersPerPx < 50 {
                    lead -= Double(point.y - targetY) * metersPerPx * 0.5
                }
            }
            lead = min(max(lead, 0), distance)
            chaseLead = lead
            let ahead = MapChase.offset(position, meters: lead, heading: heading)
            let camera = MKMapCamera(lookingAtCenter: ahead, fromDistance: distance, pitch: 60, heading: heading)
            if first {
                holdUntil = Date().addingTimeInterval(1.1)
                UIView.animate(withDuration: 1.05, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                    map.camera = camera
                }
            } else {
                UIView.animate(withDuration: Self.tick, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) {
                    map.camera = camera
                }
            }
        }

        private func headingTarget(_ position: CLLocationCoordinate2D, entry: FocusEntry) -> Double? {
            if let motion = entry.motion, let shown = entry.shown, let shape = ShapeStore.shared.shape(motion.s) {
                let ahead = LiveMotionEstimator.pointAt(shape, shown.along + 45)
                if MapChase.meters(position, ahead) > 2 { return MapChase.bearing(position, ahead) }
            }
            if let line = focusLine {
                let near = focusAlong ?? Self.nearestAlong(line, position)
                if let hit = Onboard.projectOnShape(line, lat: position.latitude, lon: position.longitude, near: near), hit.dist < 80 {
                    focusAlong = hit.along
                    let ahead = LiveMotionEstimator.pointAt(line, hit.along + 45)
                    if MapChase.meters(position, ahead) > 2 { return MapChase.bearing(position, ahead) }
                }
            }
            if let last = lastHeadingPoint, MapChase.meters(last, position) >= 12 {
                lastHeadingPoint = position
                return MapChase.bearing(last, position)
            }
            if lastHeadingPoint == nil { lastHeadingPoint = position }
            if let chaseHeading { return chaseHeading }
            return entry.bearing.flatMap { $0 > 0 ? $0 : nil }
        }

        private static func nearestAlong(_ line: ShapeLine, _ p: CLLocationCoordinate2D) -> Double {
            var best = (along: 0.0, d: Double.infinity)
            for (i, pt) in line.pts.enumerated() where pt.count >= 2 {
                let d = MapChase.meters(p, CLLocationCoordinate2D(latitude: pt[0], longitude: pt[1]))
                if d < best.d { best = (line.cum[i], d) }
            }
            return best.along
        }

        func resumeFollow() {
            followPaused = false
            guard let map, let focus else { return }
            if parent.is3D {
                followCentered = false
                return
            }
            holdUntil = Date().addingTimeInterval(Self.recenterHold)
            let point = map.convert(focus.annotation.coordinate, toPointTo: map)
            let target = visibleCenterPoint(in: map)
            let center = map.convert(CGPoint(x: map.bounds.midX + point.x - target.x, y: map.bounds.midY + point.y - target.y), toCoordinateFrom: map)
            let camera = map.camera.copy() as? MKMapCamera ?? MKMapCamera()
            camera.centerCoordinate = center
            UIView.animate(withDuration: Self.recenterHold - 0.05, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                map.camera = camera
            }
        }

        func zoom(by delta: Double) {
            guard let map else { return }
            map.setCenter(map.centerCoordinate, zoomLevel: map.zoomLevel + delta, animated: true)
        }

        // MARK: Route shapes, traffic, position

        func applyRouteShapes(to map: MKMapView) {
            let p = parent
            let active = p.filters.shape ? p.filters.routes : []
            let signature = active.sorted().joined(separator: ",") + "|" + active.filter { p.routeShapes[$0] != nil }.joined(separator: ",")
            guard signature != shapeSignature else { return }
            shapeSignature = signature
            map.removeOverlays(shapeOverlays)
            shapeOverlays = []
            var created: [RouteOverlay] = []
            for routeId in active {
                guard let lines = p.routeShapes[routeId] else { continue }
                let colorHex = p.routes[routeId]?.color ?? "1FB574"
                for line in lines where line.count > 1 {
                    let halo = RouteOverlay(coordinates: line, count: line.count)
                    halo.isHalo = true
                    halo.colorHex = colorHex
                    let stroke = RouteOverlay(coordinates: line, count: line.count)
                    stroke.colorHex = colorHex
                    created.append(contentsOf: [halo, stroke])
                }
            }
            shapeOverlays = created
            map.addOverlays(created, level: .aboveRoads)
        }

        func applyTraffic(to map: MKMapView) {
            let segments = parent.filters.traffic && !parent.historyOn ? parent.traffic : []
            let signature = segments.map { "\($0.id):\($0.level)" }.joined(separator: ";")
            guard signature != trafficSignature else { return }
            trafficSignature = signature
            map.removeOverlays(trafficOverlays)
            trafficOverlays = []
            for segment in segments {
                let coordinates = segment.path.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
                guard coordinates.count > 1 else { continue }
                let halo = TrafficOverlay(coordinates: coordinates, count: coordinates.count)
                halo.isHalo = true
                halo.level = segment.level
                let line = TrafficOverlay(coordinates: coordinates, count: coordinates.count)
                line.level = segment.level
                line.segment = segment
                trafficOverlays.append(contentsOf: [halo, line])
            }
            map.addOverlays(trafficOverlays, level: .aboveRoads)
        }

        func applyUserPosition(_ position: GeoPosition?, to map: MKMapView) {
            guard let position else {
                if let userDot { map.removeAnnotation(userDot) }
                if let accuracy { map.removeOverlay(accuracy) }
                userDot = nil
                accuracy = nil
                accuracySignature = ""
                return
            }
            let coordinate = position.coordinate
            if let userDot {
                userDot.coordinate = coordinate
            } else {
                let dot = UserDotAnnotation(coordinate: coordinate)
                userDot = dot
                map.addAnnotation(dot)
            }
            let radius = max(position.accuracyM, 12)
            let signature = "\(coordinate.latitude),\(coordinate.longitude),\(radius)"
            guard signature != accuracySignature else { return }
            accuracySignature = signature
            if let accuracy { map.removeOverlay(accuracy) }
            let circle = AccuracyCircle(center: coordinate, radius: radius)
            accuracy = circle
            map.addOverlay(circle, level: .aboveRoads)
        }

        // MARK: Timeline

        func renderHistory(_ t: Double, frames: MapHistoryFrames, options: MapHistoryRenderOptions) -> MapHistoryRenderResult {
            guard let map else { return lastHistory }
            let start = MapHistoryData.windowStart(of: t)
            guard let current = frames.get(start) else {
                setHistoryStale(true, in: map)
                lastHistory = MapHistoryRenderResult(ready: false, visible: lastHistory.visible)
                return lastHistory
            }
            setHistoryStale(false, in: map)
            if zooming { return lastHistory }
            let prev = frames.get(start - MapHistoryData.windowSec)
            let next = frames.get(start + MapHistoryData.windowSec)
            historyFrame += 1
            let frame = historyFrame
            var visible = 0
            var add: [VehicleAnnotation] = []

            for (id, track) in current.tracks {
                let existing = history[id]
                let hint = existing?.windowStart == start ? existing?.hint ?? -1 : -1
                guard let sample = MapHistorySampler.sample(track, t, hint: hint, prev: prev?.tracks[id], next: next?.tracks[id]) else { continue }
                let ref = sample.a ?? sample.b
                let routeShort = ref.map { $0.track.routeAt($0.i) } ?? track.route
                guard options.isVisible(id, routeShort) else { continue }
                let coordinate = CLLocationCoordinate2D(latitude: sample.lat, longitude: sample.lon)
                let tracked = options.isTracked(id)
                let route = routeShort.flatMap { options.routeByShort[$0] }
                let iconKey = "\(routeShort ?? "")|\(route?.color ?? "")|\(route?.text ?? "")|\(tracked)|\(options.showIds)"
                var state = existing ?? HistoryState(
                    annotation: VehicleAnnotation(
                        vehicleId: id, tripId: track.trip ?? "", routeShort: "?", routeColor: "1FB574", routeText: "FFFFFF",
                        headsign: "", coordinate: coordinate, tracked: false, labelText: nil, mode: nil, estimated: false,
                        dimmed: false, isHistory: true
                    ),
                    iconKey: "", shown: false, hint: -1, windowStart: start, frame: 0, route: nil, sample: nil
                )
                state.hint = sample.index
                state.windowStart = start
                state.frame = frame
                state.route = routeShort
                state.sample = sample
                if iconKey != state.iconKey {
                    state.iconKey = iconKey
                    let a = state.annotation
                    a.routeShort = route?.short ?? routeShort ?? "?"
                    a.routeColor = route?.color ?? "1FB574"
                    a.routeText = route?.text ?? "FFFFFF"
                    a.tracked = tracked
                    a.mode = TransitIds.vehicleMode(id: id, mode: nil, routeType: route?.type)
                    a.labelText = options.showIds || tracked ? TransitIds.displayVehicleId(id) : nil
                    (map.view(for: a) as? VehicleAnnotationView)?.apply()
                }
                state.annotation.coordinate = coordinate
                if !state.shown {
                    add.append(state.annotation)
                    state.shown = true
                }
                history[id] = state
                visible += 1
            }
            var remove: [VehicleAnnotation] = []
            for (id, state) in history where state.frame != frame && state.shown {
                remove.append(state.annotation)
                history[id]?.shown = false
            }
            if !remove.isEmpty { map.removeAnnotations(remove) }
            if !add.isEmpty { map.addAnnotations(add) }
            lastHistory = MapHistoryRenderResult(ready: true, visible: visible)
            return lastHistory
        }

        private func setHistoryStale(_ stale: Bool, in map: MKMapView) {
            guard historyStale != stale else { return }
            historyStale = stale
            for state in history.values where state.shown {
                map.view(for: state.annotation)?.alpha = stale ? 0.35 : 1
            }
        }

        func historySample(_ id: String) -> (sample: MapHistorySampler.Sample?, route: String?) {
            (history[id]?.sample, history[id]?.route)
        }

        func clearHistory() {
            guard let map else { return }
            map.removeAnnotations(history.values.map(\.annotation))
            history = [:]
            lastHistory = MapHistoryRenderResult(ready: false, visible: 0)
        }

        // MARK: Camera commands

        func run(_ command: MapCommand, on map: MKMapView) {
            switch command {
            case .fly(let coordinate, let zoom):
                map.setCenter(coordinate, zoomLevel: zoom, animated: true)
            case .jump(let coordinate, let zoom):
                map.setCenter(coordinate, zoomLevel: zoom, animated: false)
            case .fit(let coordinates, let maxZoom):
                map.fit(coordinates, maxZoom: maxZoom, padding: 80)
            case .flyAtLeast(let coordinate, let minZoom):
                map.setCenter(coordinate, zoomLevel: max(map.zoomLevel, minZoom), animated: true)
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
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
            if let traffic = overlay as? TrafficOverlay {
                let renderer = MKPolylineRenderer(polyline: traffic)
                renderer.lineCap = .round
                renderer.lineJoin = .round
                let weight = 5 + (traffic.level * 3).rounded()
                if traffic.isHalo {
                    renderer.strokeColor = UIColor(Theme.background).withAlphaComponent(0.55)
                    renderer.lineWidth = weight + 4
                } else {
                    renderer.strokeColor = TrafficColor.uiColor(traffic.level).withAlphaComponent(0.95)
                    renderer.lineWidth = weight
                }
                return renderer
            }
            if let circle = overlay as? AccuracyCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor(Theme.early).withAlphaComponent(0.12)
                renderer.strokeColor = UIColor(Theme.early).withAlphaComponent(0.5)
                renderer.lineWidth = 1
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is StopAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: StopAnnotationView.reuseIdentifier, for: annotation)
                view.annotation = annotation
                return view
            case let vehicle as VehicleAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: VehicleAnnotationView.reuseIdentifier, for: annotation)
                view.annotation = annotation
                view.isEnabled = !vehicle.isFocus
                if vehicle.isHistory { view.alpha = historyStale ? 0.35 : 1 }
                return view
            case is UserDotAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: UserDotAnnotationView.reuseIdentifier, for: annotation)
                view.annotation = annotation
                view.isEnabled = false
                return view
            default:
                return nil
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)
            if let stop = annotation as? StopAnnotation {
                parent.onSelectStop(stop.stopId)
            } else if let vehicle = annotation as? VehicleAnnotation, !vehicle.isFocus {
                UISelectionFeedbackGenerator().selectionChanged()
                if vehicle.isHistory {
                    parent.onSelectHistoryVehicle(vehicle.vehicleId)
                } else {
                    parent.onSelectVehicle(vehicle.vehicleId)
                }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let zoom = mapView.zoomLevel
            let center = mapView.centerCoordinate
            parent.camera.updateZoom(zoom)

            let previous = stopZoom
            if !(zoom < Self.coachStopsZoom && previous < Self.coachStopsZoom) {
                let rect = mapView.visibleMapRect
                let padded = rect.insetBy(dx: -rect.width * 0.35, dy: -rect.height * 0.35)
                let moved = stopBounds.map { !$0.contains(MKMapPoint(x: rect.minX, y: rect.minY)) || !$0.contains(MKMapPoint(x: rect.maxX, y: rect.maxY)) } ?? true
                if moved || (zoom >= Self.coachStopsZoom) != (previous >= Self.coachStopsZoom) {
                    stopBounds = padded
                }
            }
            stopZoom = zoom
            applyStops(to: mapView)

            persistWork?.cancel()
            let work = DispatchWorkItem {
                ViewStateStore.save(ViewStateStore.MapView(lat: center.latitude, lon: center.longitude, zoom: zoom))
            }
            persistWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }
}

/// The 3D chase camera's maths (`map3d/chaseCam.ts`).
enum MapChase {
    private static let mPerDegLat = 110_540.0
    private static let mPerDegLon = 111_320.0

    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let kx = mPerDegLon * cos((a.latitude + b.latitude) / 2 * .pi / 180)
        return hypot((b.longitude - a.longitude) * kx, (b.latitude - a.latitude) * mPerDegLat)
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let kx = mPerDegLon * cos((a.latitude + b.latitude) / 2 * .pi / 180)
        let deg = atan2((b.longitude - a.longitude) * kx, (b.latitude - a.latitude) * mPerDegLat) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    static func delta(_ from: Double, _ to: Double) -> Double {
        let d = ((to - from).truncatingRemainder(dividingBy: 360) + 540).truncatingRemainder(dividingBy: 360) - 180
        return d == -180 ? 180 : d
    }

    /// Turns towards `target` with time constant `tau`, never faster than `maxDegPerS`.
    static func approach(_ current: Double, _ target: Double, dt: Double, tau: Double = 0.9, maxDegPerS: Double = 75) -> Double {
        let d = delta(current, target)
        let share = 1 - exp(-max(0, dt) / tau)
        let limit = maxDegPerS * max(0, dt)
        let step = max(-limit, min(limit, d * share))
        return (current + step + 360).truncatingRemainder(dividingBy: 360)
    }

    static func offset(_ c: CLLocationCoordinate2D, meters: Double, heading: Double) -> CLLocationCoordinate2D {
        let rad = heading * .pi / 180
        let kx = mPerDegLon * cos(c.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: c.latitude + meters * cos(rad) / mPerDegLat,
            longitude: c.longitude + meters * sin(rad) / kx
        )
    }
}
