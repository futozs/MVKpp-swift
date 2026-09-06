//
//  ArrivalRowView.swift
//  MVK++ Watch App
//

import SwiftUI

/// One row in a stop's full arrival list. Tappable to "pin"/follow that trip.
struct ArrivalRowView: View {
    let arrival: ArrivalItem

    var body: some View {
        ArrivalCardView(
            route: arrival.route,
            color: arrival.color,
            text: arrival.text,
            delaySec: arrival.delaySec,
            vehicleId: arrival.vehicle?.id,
            etaMin: arrival.etaMin
        )
    }
}
