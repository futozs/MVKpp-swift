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
                if let url = note.object as? URL {
                    PhoneAppDelegate.pendingLink = nil
                    open(url)
                }
            }
            .task {
                CloudSync.shared.start()
                RideController.shared.attach(location: location, transit: store)
                PushService.shared.start()
                PhoneWatchBridge.shared.start()
                if let pending = PhoneAppDelegate.pendingLink {
                    PhoneAppDelegate.pendingLink = nil
                    open(pending)
                }
            }
    }

    /// `mvkpp://` links (widgets, intents) and links into the web app
    /// (universal links, a push's `url`).
    private func open(_ url: URL) {
        if let link = DeepLink(url: url) {
            open(link)
        } else if let link = WebLink(url: url) {
            // A linked stop is put on the watchlist, or the link would lead
            // nowhere (web `applyLink`).
            if case .app(_, let stopId?) = link, !favorites.contains(stopId) {
                favorites.add(stopId)
            }
            navigation.open(link)
        }
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
    @MainActor static var pendingLink: URL?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before returning: the tap that cold-started the app is delivered
        // right after launch and is lost without a delegate in place.
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated {
            BackgroundRefresh.register()
            Task { await NotificationCenterStore.shared.configure() }
        }
        return true
    }

    /// Portrait, except while the kiosk board is up: in landscape it shows
    /// its stops side by side.
    @MainActor private static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { Self.orientations }
    }

    @MainActor static func allowLandscape(_ allowed: Bool) {
        orientations = allowed ? .allButUpsideDown : .portrait
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            var controller = scene.keyWindow?.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
            if !allowed { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushService.shared.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// Without this, iOS delivers a notification silently while the app is in
    /// the foreground, exactly when someone tests an arrival alarm.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// A tap opens the push's `url` (`/?stop=SP12#multistop`); a local
    /// alarm carries only its stop, for the Megállófigyelő.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let url = (info["url"] as? String).flatMap(WebLink.resolve)
            ?? (info["stopId"] as? String).map { DeepLink.watchlist($0).url }
        guard let url else { return }
        await MainActor.run {
            PhoneAppDelegate.pendingLink = url
            NotificationCenter.default.post(name: .mvkOpenLink, object: url)
        }
    }
}
