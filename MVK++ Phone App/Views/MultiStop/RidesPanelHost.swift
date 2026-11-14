//
//  RidesPanelHost.swift
//  MVK++ Phone App
//

import SwiftUI

/// The Figyelő's „Utazásaim” view. The ride log itself (the web app's
/// `RidesPanel`) belongs to the ride feature; this is where it is mounted.
struct RidesPanelHost: View {
    var body: some View {
        ContentUnavailableView(
            "Utazásaim",
            systemImage: "ticket",
            description: Text("Az utazásnapló itt jelenik meg.")
        )
        .foregroundStyle(Theme.mutedForeground)
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}
