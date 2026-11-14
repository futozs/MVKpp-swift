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
    let isWatched: Bool
    let isSelected: Bool
    let isRail: Bool
    /// Zoomed in close (≥ 14): bigger dots.
    let isClose: Bool

    init(stop: Stop, isWatched: Bool, isSelected: Bool, isClose: Bool) {
        stopId = stop.id
        coordinate = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon)
        title = stop.name
        self.isWatched = isWatched
        self.isSelected = isSelected
        isRail = (stop.feed ?? TransitFeed.of(id: stop.id).rawValue) == "rail"
        self.isClose = isClose
    }
}

/// A stop dot — the web's canvas circle marker: grey at city distance, a
/// little bigger up close, brand green when watched or selected, MÁV blue for
/// a railway station. The view itself is finger-sized (the web's 15 px hit
/// tolerance).
final class StopAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "StopAnnotationView"
    static let railColor = UIColor(red: 0x1E / 255, green: 0x5A / 255, blue: 0xA8 / 255, alpha: 1)
    static let stopZPriority = MKAnnotationViewZPriority(rawValue: 100)

    private let dot = CALayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        backgroundColor = .clear
        layer.addSublayer(dot)
        collisionMode = .none
        displayPriority = .required
        zPriority = Self.stopZPriority
    }

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
        let radius: CGFloat = active ? 7.5 : stop.isRail ? 6.5 : stop.isClose ? 5 : 3
        let border: CGFloat = stop.isRail ? 2 : (stop.isClose || active) ? 1.5 : 1
        let diameter = radius * 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.frame = CGRect(x: (bounds.width - diameter) / 2, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
        dot.cornerRadius = radius
        dot.backgroundColor = (active ? UIColor(Theme.primary) : stop.isRail ? Self.railColor : UIColor(Theme.mutedForeground)).cgColor
        dot.borderWidth = border
        dot.borderColor = UIColor(Theme.background).cgColor
        CATransaction.commit()

        zPriority = Self.stopZPriority
        accessibilityLabel = stop.title
    }
}

// MARK: - The rider's position

final class UserDotAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String? = "Itt vagy"

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

/// The web's own location marker: an `--early` blue dot with a background ring.
final class UserDotAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "UserDotAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        let dot = UIView(frame: bounds)
        dot.backgroundColor = UIColor(Theme.early)
        dot.layer.cornerRadius = 10
        dot.layer.borderWidth = 3
        dot.layer.borderColor = UIColor(Theme.background).cgColor
        dot.isUserInteractionEnabled = false
        addSubview(dot)
        collisionMode = .none
        displayPriority = .required
        zPriority = MKAnnotationViewZPriority(rawValue: 950)
        isAccessibilityElement = true
        accessibilityLabel = "Itt vagy"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
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
    /// KVO-observable so MapKit moves the marker (and its index) with it.
    @objc dynamic var coordinate: CLLocationCoordinate2D
    /// Pinned by the rider (or matching the typed query): ring, kept on top.
    var tracked: Bool
    /// The id under the tile (the train number for a train).
    var labelText: String?
    var mode: TransitMode?
    /// Position estimated from the timetable, not GPS: dashed and faded.
    var estimated: Bool
    /// Another vehicle is being followed: this one is shown faded.
    var dimmed: Bool
    /// The followed vehicle, drawn above everything.
    var isFocus: Bool
    /// A replayed vehicle on the timeline.
    var isHistory: Bool

    init(
        vehicleId: String, tripId: String, routeShort: String, routeColor: String, routeText: String, headsign: String,
        coordinate: CLLocationCoordinate2D, tracked: Bool, labelText: String?, mode: TransitMode?, estimated: Bool,
        dimmed: Bool, isFocus: Bool = false, isHistory: Bool = false
    ) {
        self.vehicleId = vehicleId
        self.tripId = tripId
        self.routeShort = routeShort.isEmpty ? "?" : routeShort
        self.routeColor = routeColor
        self.routeText = routeText
        self.headsign = headsign
        self.coordinate = coordinate
        self.tracked = tracked
        self.labelText = labelText
        self.mode = mode
        self.estimated = estimated
        self.dimmed = dimmed
        self.isFocus = isFocus
        self.isHistory = isHistory
    }

    var renderKey: String {
        "\(routeShort)|\(routeColor)|\(routeText)|\(tracked)|\(labelText ?? "")|\(dimmed)|\(mode?.rawValue ?? "")|\(estimated)|\(isFocus)"
    }

    func absorb(_ other: VehicleAnnotation) {
        tripId = other.tripId
        routeShort = other.routeShort
        routeColor = other.routeColor
        routeText = other.routeText
        headsign = other.headsign
        tracked = other.tracked
        labelText = other.labelText
        mode = other.mode
        estimated = other.estimated
        dimmed = other.dimmed
        isFocus = other.isFocus
    }
}

/// The route-number tile with the id beneath it — the web's `.mvk-vehicle`:
/// a Volán coach's tile is squarer, a train's a capsule with its category, an
/// estimated position dashed and faded, a tracked one ringed in brand green.
final class VehicleAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "VehicleAnnotationView"
    static let vehicleZPriority = MKAnnotationViewZPriority(rawValue: 900)

    private let tile = UILabel()
    private let ring = UIView()
    private let dash = CAShapeLayer()
    private let plate = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        collisionMode = .none

        ring.isUserInteractionEnabled = false
        ring.layer.cornerCurve = .continuous
        ring.layer.borderWidth = 2
        ring.layer.borderColor = UIColor(Theme.primary).cgColor
        ring.backgroundColor = .clear
        addSubview(ring)

        tile.textAlignment = .center
        tile.font = .systemFont(ofSize: 11, weight: .heavy)
        tile.layer.cornerCurve = .continuous
        tile.layer.borderColor = UIColor.black.withAlphaComponent(0.55).cgColor
        tile.clipsToBounds = true
        addSubview(tile)

        dash.fillColor = UIColor.clear.cgColor
        dash.strokeColor = UIColor.black.withAlphaComponent(0.55).cgColor
        dash.lineWidth = 1
        dash.lineDashPattern = [3, 2]
        layer.addSublayer(dash)

        plate.textAlignment = .center
        plate.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        plate.backgroundColor = UIColor(Theme.popover).withAlphaComponent(0.97)
        plate.layer.cornerRadius = 5
        plate.layer.cornerCurve = .continuous
        plate.layer.borderWidth = 1
        plate.clipsToBounds = true
        addSubview(plate)

        layer.shadowColor = UIColor(Theme.Shadow.color).cgColor
        layer.shadowOpacity = 0.75
        layer.shadowRadius = 4.5
        layer.shadowOffset = CGSize(width: 0, height: 3)
    }

    override var annotation: MKAnnotation? {
        didSet { apply() }
    }

    func apply() {
        guard let vehicle = annotation as? VehicleAnnotation else { return }
        let rail = vehicle.mode == .rail
        let coach = vehicle.mode == .coach

        tile.text = vehicle.routeShort
        tile.backgroundColor = UIColor(Theme.hex(vehicle.routeColor))
        tile.textColor = UIColor(Theme.hex(vehicle.routeText, fallback: .white))
        let padding: CGFloat = rail ? 14 : 10
        let tileWidth = max(27, tile.intrinsicContentSize.width + padding)
        let radius: CGFloat = rail ? 9.5 : coach ? 3 : 6
        tile.layer.cornerRadius = radius
        tile.layer.borderWidth = vehicle.estimated ? 0 : 1
        tile.alpha = vehicle.estimated ? 0.72 : 1

        if let text = vehicle.labelText {
            plate.isHidden = false
            plate.text = text
            plate.textColor = vehicle.tracked ? UIColor(Theme.signal200) : UIColor(Theme.foreground)
            plate.layer.borderColor = vehicle.tracked
                ? UIColor(Theme.primary).withAlphaComponent(0.6).cgColor
                : UIColor(Theme.border).cgColor
            plate.frame.size = CGSize(width: plate.intrinsicContentSize.width + 8, height: 14)
        } else {
            plate.isHidden = true
        }

        let ringPad: CGFloat = 4
        let width = max(tileWidth + ringPad * 2, plate.isHidden ? 0 : plate.frame.width)
        let height: CGFloat = plate.isHidden ? 19 + ringPad * 2 : 19 + ringPad + 4 + 14
        bounds = CGRect(x: 0, y: 0, width: width, height: height)

        let tileFrame = CGRect(x: (width - tileWidth) / 2, y: ringPad, width: tileWidth, height: 19)
        tile.frame = tileFrame
        ring.isHidden = !vehicle.tracked
        ring.frame = tileFrame.insetBy(dx: -4, dy: -4)
        ring.layer.cornerRadius = radius + 4
        ring.layer.borderWidth = 2
        ring.layer.borderColor = UIColor(Theme.primary).cgColor
        ring.layer.shadowColor = UIColor(Theme.background).cgColor
        ring.layer.shadowOpacity = vehicle.tracked ? 1 : 0
        ring.layer.shadowRadius = 0
        ring.layer.shadowOffset = .zero

        dash.isHidden = !vehicle.estimated
        dash.frame = tileFrame
        dash.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: tileFrame.size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius).cgPath

        if !plate.isHidden {
            plate.frame.origin = CGPoint(x: (width - plate.frame.width) / 2, y: tileFrame.maxY + 4)
        }

        centerOffset = CGPoint(x: 0, y: height / 2 - tileFrame.midY)
        alpha = vehicle.dimmed ? 0.55 : 1
        zPriority = vehicle.isFocus ? .max : vehicle.tracked ? MKAnnotationViewZPriority(rawValue: 990) : Self.vehicleZPriority
        displayPriority = .required
        layer.shadowColor = vehicle.tracked
            ? UIColor(Theme.primary).withAlphaComponent(0.45).cgColor
            : UIColor(Theme.Shadow.color).cgColor

        let label = vehicle.labelText.map { ", \($0)" } ?? ""
        accessibilityLabel = "\(vehicle.routeShort) — \(vehicle.headsign)\(label)"
    }
}

// MARK: - Overlays

/// Route shapes and the followed trip's path are drawn twice: a wide
/// background-coloured halo under the route colour on top.
final class RouteOverlay: MKPolyline {
    var colorHex: String = "1FB574"
    var isHalo = false
    var isFocus = false
}

/// A congested link, coloured by its level.
final class TrafficOverlay: MKPolyline {
    var level: Double = 0
    var isHalo = false
    var segment: MapTrafficSegment?
}

final class AccuracyCircle: MKCircle {}
