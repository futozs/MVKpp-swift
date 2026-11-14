//
//  RideLayer.swift
//  MVK++ Phone App
//

import SwiftUI

/// The map's ride layer: boarding detection, the ride panel and the summary
/// after the ride. While riding the map follows the bus.
struct RideLayer: View {
    let vehicles: [LiveVehicle]
    /// The trip the map is following right now.
    let followingTripId: String?
    let onFollow: (_ tripId: String, _ vehicleId: String) -> Void
    let onStopFollow: () -> Void

    var body: some View {
        EmptyView()
    }
}
