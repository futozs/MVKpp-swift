//
//  RideHaptics.swift
//  MVK++ Phone App
//

import UIKit

/// The ride's moments, felt: boarding, the bus reaching the next stop, the
/// stop before the rider's own, and getting off.
@MainActor
enum RideHaptics {
    static func boarded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func detected() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func nextStop() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// One stop before the rider's own: two firm taps.
    static func approachingDestination() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            generator.impactOccurred()
        }
    }

    static func alighted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
