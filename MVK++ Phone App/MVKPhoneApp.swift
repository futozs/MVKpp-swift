//
//  MVKPhoneApp.swift
//  MVK++ Phone App
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct MVKPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate
    @ObservedObject private var reloader = AppReloader.shared

    var body: some Scene {
        WindowGroup {
            // A new generation rebuilds every store from storage — how
            // settings that arrived from another device are taken over.
            AppRoot()
                .id(reloader.generation)
        }
    }
}

/// Owns the app's stores for one generation.
struct AppRoot: View {
    @StateObject private var store = TransitStore()
    @StateObject private var navigation = AppNavigation()
    @StateObject private var location = LocationProvider()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var lineFavorites = LineFavoritesStore()

    var body: some View {
        RootTabView()
            .environmentObject(store)
            .environmentObject(navigation)
            .environmentObject(location)
            .environmentObject(favorites)
            .environmentObject(lineFavorites)
            .tint(Theme.primary)
            .preferredColorScheme(.dark)
            .onOpenURL(perform: open)
            .onReceive(NotificationCenter.default.publisher(for: .mvkOpenLink)) { note in
                if let link = note.object as? DeepLink {
                    PhoneAppDelegate.pendingLink = nil
                    open(link)
                }
            }
            .task {
                CloudSync.shared.start()
                RideController.shared.attach(location: location, transit: store)
                PushService.shared.start()
                if let pending = PhoneAppDelegate.pendingLink {
                    PhoneAppDelegate.pendingLink = nil
                    open(pending)
                }
            }
    }

    private func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        open(link)
    }

    private func open(_ link: DeepLink) {
        // The Megállófigyelő only has a card for a stop it is watching, so a
        // link that lands there puts it on the list first.
        if case .watchlist(let stopId) = link, !favorites.contains(stopId) {
            favorites.add(stopId)
        }
        navigation.open(link)
    }
}

extension Notification.Name {
    /// A notification tap asks the app to open a stop.
    static let mvkOpenLink = Notification.Name("mvk-open-link")
}

/// Launch-time wiring that needs UIKit: background refresh, the APNs device
/// token, and notification taps.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// A tap that arrived before the UI was listening (cold start).
    @MainActor static var pendingLink: DeepLink?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated {
            BackgroundRefresh.register()
            Task {
                await NotificationCenterStore.shared.configure()
                // Set after `configure()`, which installs the shared presenter.
                UNUserNotificationCenter.current().delegate = self
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushService.shared.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// A tap brings the app forward with that stop in the Megállófigyelő.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let stopId = response.notification.request.content.userInfo["stopId"] as? String else { return }
        await MainActor.run {
            let link = DeepLink.watchlist(stopId)
            PhoneAppDelegate.pendingLink = link
            NotificationCenter.default.post(name: .mvkOpenLink, object: link)
        }
    }
}
