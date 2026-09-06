//
//  MapAnnotations.swift
//  MVK++ Phone App
//

import MapKit
import SwiftUI
import UIKit

// MARK: - Stops

final class StopAnnotation: NSObject, MKAnnotation {
    let stopId: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    var isWatched: Bool
    var isSelected: Bool

    init(stop: Stop, isWatched: Bool, isSelected: Bool) {
        stopId = stop.id
        coordinate = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon)
        title = stop.name
        self.isWatched = isWatched
        self.isSelected = isSelected
    }
}

/// A stop dot. The drawn circle stays small so the map does not turn into a
/// field of blobs, but the view itself is finger-sized — the web app solves the
/// same problem with a 15 px canvas hit tolerance.
final class StopAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "StopAnnotationView"

    private let dot = CALayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    // These views are only ever created by MapKit's reuse queue, never from a
    // nib — but the superclass requires the initializer, so it stays.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        centerOffset = .zero
        backgroundColor = .clear
        layer.addSublayer(dot)
        // No collision culling: the web draws every stop, and MapKit was
        // hiding whole clusters of them at city zoom.
        collisionMode = .none
        displayPriority = .required
        zPriority = Self.stopZPriority
    }

    /// Stops sit under the vehicle tiles — a grey dot must never cover a
    /// route number.
    static let stopZPriority = MKAnnotationViewZPriority(rawValue: 100)

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
    }

    override var annotation: MKAnnotation? {
        didSet { apply() }
    }

    private func apply() {
        guard let stop = annotation as? StopAnnotation else { return }
        let active = stop.isWatched || stop.isSelected
        let diameter: CGFloat = active ? 15 : 10

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.frame = CGRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        dot.cornerRadius = diameter / 2
        dot.backgroundColor = (active ? UIColor(Theme.primary) : UIColor(Theme.mutedForeground)).cgColor
        dot.borderWidth = 1.5
        dot.borderColor = UIColor(Theme.background).cgColor
        CATransaction.commit()

        zPriority = Self.stopZPriority
        accessibilityLabel = stop.title
    }
}

// MARK: - Vehicles

final class VehicleAnnotation: NSObject, MKAnnotation, Identifiable {
    var id: String { vehicleId }

    let vehicleId: String
    var tripId: String
    var routeShort: String
    var routeColor: String
    var routeText: String
    var headsign: String
    var speed: Double?
    var coordinate: CLLocationCoordinate2D
    /// Pinned by the rider (or matching the typed query) — drawn with a ring
    /// and kept on top.
    var tracked: Bool
    /// Registration number shown under the tile.
    var labelText: String?

    init(vehicle: LiveVehicle, tracked: Bool, showLabel: Bool) {
        vehicleId = vehicle.id
        tripId = vehicle.tripId
        routeShort = vehicle.routeShort.isEmpty ? "?" : vehicle.routeShort
        routeColor = vehicle.routeColor
        routeText = vehicle.routeText
        headsign = vehicle.headsign
        speed = vehicle.speed
        coordinate = vehicle.coordinate ?? CLLocationCoordinate2D()
        self.tracked = tracked
        labelText = (showLabel || tracked) ? vehicle.id : nil
    }

    init(tripPath: TripPathResponse, vehicle: ArrivalVehicle) {
        vehicleId = vehicle.id
        tripId = tripPath.trip
        routeShort = tripPath.route
        routeColor = tripPath.color
        routeText = tripPath.text
        headsign = tripPath.headsign
        speed = vehicle.speed
        coordinate = CLLocationCoordinate2D(latitude: vehicle.lat, longitude: vehicle.lon)
        tracked = true
        labelText = vehicle.id
    }

    /// What distinguishes one rendering of this vehicle from another. Used to
    /// decide whether an existing annotation only needs redrawing.
    var renderKey: String {
        "\(vehicleId)|\(routeShort)|\(routeColor)|\(tracked)|\(labelText ?? "")"
    }

    /// Copies everything the feed can change, so the annotation object — and
    /// with it the view MapKit already has on screen — survives the update.
    func absorb(_ other: VehicleAnnotation) {
        tripId = other.tripId
        routeShort = other.routeShort
        routeColor = other.routeColor
        routeText = other.routeText
        headsign = other.headsign
        speed = other.speed
        tracked = other.tracked
        labelText = other.labelText
    }
}

/// The route-number tile that marks a vehicle, with the registration number
/// beneath it — a direct port of the web app's `.mvk-vehicle` marker.
final class VehicleAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "VehicleAnnotationView"

    /// Above every stop dot, below the followed vehicle.
    static let vehicleZPriority = MKAnnotationViewZPriority(rawValue: 900)

    private let tile = UILabel()
    private let ring = UIView()
    private let plate = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    // These views are only ever created by MapKit's reuse queue, never from a
    // nib — but the superclass requires the initializer, so it stays.
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        collisionMode = .none

        ring.isUserInteractionEnabled = false
        ring.layer.cornerRadius = 9
        ring.layer.cornerCurve = .continuous
        ring.layer.borderWidth = 2
        ring.layer.borderColor = UIColor(Theme.primary).cgColor
        addSubview(ring)

        tile.textAlignment = .center
        tile.font = .systemFont(ofSize: 11, weight: .heavy)
        tile.layer.cornerRadius = 6
        tile.layer.cornerCurve = .continuous
        tile.layer.borderWidth = 1
        tile.layer.borderColor = UIColor.black.withAlphaComponent(0.55).cgColor
        tile.layer.masksToBounds = false
        tile.clipsToBounds = true
        addSubview(tile)

        plate.textAlignment = .center
        plate.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        plate.textColor = UIColor(Theme.foreground)
        plate.backgroundColor = UIColor(Theme.popover).withAlphaComponent(0.97)
        plate.layer.cornerRadius = 5
        plate.layer.cornerCurve = .continuous
        plate.layer.borderWidth = 1
        plate.layer.borderColor = UIColor(Theme.border).cgColor
        plate.clipsToBounds = true
        addSubview(plate)

        // The shadow lives on the annotation view, not the clipped tile.
        layer.shadowColor = UIColor(Theme.Shadow.color).cgColor
        layer.shadowOpacity = 0.75
        layer.shadowRadius = 4.5
        layer.shadowOffset = CGSize(width: 0, height: 3)
    }

    override var annotation: MKAnnotation? {
        didSet { apply() }
    }

    private func apply() {
        guard let vehicle = annotation as? VehicleAnnotation else { return }

        tile.text = vehicle.routeShort
        tile.backgroundColor = UIColor(Theme.hex(vehicle.routeColor))
        tile.textColor = UIColor(Theme.hex(vehicle.routeText, fallback: .white))

        let tileWidth = max(27, tile.intrinsicContentSize.width + 10)
        tile.frame = CGRect(x: 0, y: 0, width: tileWidth, height: 19)

        ring.isHidden = !vehicle.tracked
        ring.frame = tile.frame.insetBy(dx: -3, dy: -3)

        if let plateText = vehicle.labelText {
            plate.isHidden = false
            plate.text = plateText
            let plateWidth = plate.intrinsicContentSize.width + 8
            plate.frame = CGRect(x: 0, y: 23, width: plateWidth, height: 14)
            plate.layer.borderColor = vehicle.tracked
                ? UIColor(Theme.primary).withAlphaComponent(0.6).cgColor
                : UIColor(Theme.border).cgColor
            plate.textColor = vehicle.tracked ? UIColor(Theme.signal200) : UIColor(Theme.foreground)
        } else {
            plate.isHidden = true
            plate.frame = .zero
        }

        // The tile is what points at the vehicle, so the view is anchored on
        // the tile's centre; the plate hangs below without shifting the pin.
        let width = max(tileWidth + 6, plate.isHidden ? 0 : plate.frame.width)
        let height: CGFloat = plate.isHidden ? 19 : 37
        bounds = CGRect(x: 0, y: 0, width: width, height: height)

        tile.frame.origin = CGPoint(x: (width - tileWidth) / 2, y: 0)
        ring.frame = tile.frame.insetBy(dx: -3, dy: -3)
        if !plate.isHidden {
            plate.frame.origin = CGPoint(x: (width - plate.frame.width) / 2, y: 23)
        }

        centerOffset = CGPoint(x: 0, y: (height / 2) - 9.5)
        zPriority = vehicle.tracked ? .max : Self.vehicleZPriority
        displayPriority = .required

        accessibilityLabel = "\(vehicle.routeShort) — \(vehicle.headsign), \(vehicle.vehicleId)"
    }
}

// MARK: - Overlay styling

/// Route shapes and the followed trip's path are drawn twice: a wide,
/// background-colored halo underneath and the route color on top, so a line
/// stays readable over both pale and satellite tiles.
final class RouteOverlay: MKPolyline {
    var colorHex: String = "1FB574"
    var isHalo = false
    var isFocus = false
}
