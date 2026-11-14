//
//  RideShortcuts.swift
//  MVK++ Phone App
//

import AppIntents

/// „Felszálltam” and „Leszálltam” for Siri, Shortcuts, Spotlight and the
/// Action button — the same intents the controls and the Live Activity use.
struct MVKPhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BoardedIntent(),
            phrases: [
                "Felszálltam \(.applicationName)",
                "\(.applicationName) felszálltam",
            ],
            shortTitle: "Felszálltam",
            systemImageName: "ticket"
        )
        AppShortcut(
            intent: AlightRideIntent(),
            phrases: [
                "Leszálltam \(.applicationName)",
                "\(.applicationName) leszálltam",
            ],
            shortTitle: "Leszálltam",
            systemImageName: "rectangle.portrait.and.arrow.right"
        )
    }
}
