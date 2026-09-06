//
//  NavigationCoordinator.swift
//  MVK++ Watch App
//

import Combine
import Foundation
import SwiftUI

/// Owns the root NavigationStack's path so deeply nested views (like the
/// trip-follow map) can pop all the way back to the home list in one tap,
/// not just one level up.
@MainActor
final class NavigationCoordinator: ObservableObject {
    @Published var path = NavigationPath()

    func popToRoot() {
        path.removeLast(path.count)
    }
}
