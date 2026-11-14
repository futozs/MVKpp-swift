//
//  BoardRideIntent.swift
//  MVK++ Phone App
//

import AppIntents

/// „Felszálltam” from Siri, Shortcuts, the Action button or Spotlight: starts
/// a ride on the vehicle the phone is next to right now.
struct BoardRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Felszálltam"
    static let description = IntentDescription("Elindítja az utazást azon a járművön, amelyik most melletted van.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await RideIntentBridge.boardNearest?() ?? "Nyisd meg az appot, és próbáld újra."
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

struct MVKPhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BoardRideIntent(),
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
