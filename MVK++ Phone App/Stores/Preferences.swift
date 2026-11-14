//
//  Preferences.swift
//  MVK++ Phone App
//

import Foundation

/// One switch in Settings: its storage key and copy (web `PrefItem`).
struct PrefItem: Identifiable, Hashable {
    let id: String
    let key: String
    let label: String
    let hint: String
}

struct ModeItem: Identifiable, Hashable {
    let id: TransitMode
    let key: String
    let label: String
    let short: String
    let hint: String
}

struct StopMergeItem: Identifiable, Hashable {
    let id: StopMerge
    let label: String
    let hint: String
}

/// The settings the web keeps under `mvk_pref_*` (`lib/modes.ts`,
/// `lib/watchPrefs.ts`), with the same keys, defaults and copy.
enum Preferences {

    // MARK: - Transport modes

    static let modeItems: [ModeItem] = [
        ModeItem(id: .tram, key: "mvk_pref_mode_tram", label: "Villamos (MVK)", short: "Villamos", hint: "Az MVK villamosai a térképen, a figyelőben, a menetrendben és a statisztikában."),
        ModeItem(id: .bus, key: "mvk_pref_mode_bus", label: "Városi busz (MVK)", short: "Busz", hint: "Az MVK buszai a városi járatok."),
        ModeItem(id: .coach, key: "mvk_pref_mode_coach", label: "Helyközi busz (Volán)", short: "Volán", hint: "A MÁV-Volán buszai Borsod-Abaúj-Zemplénben, a Búza téri autóbusz-állomással és a kocsiállásokkal."),
        ModeItem(id: .rail, key: "mvk_pref_mode_rail", label: "Vonat (MÁV)", short: "Vonat", hint: "A megyét érintő vonatok az egész útjukon: vágány, késés és oka, hol jár most."),
    ]

    /// The first-run card; synced, so one device deciding is enough.
    static let regionalIntroKey = "mvk_regional_intro"

    static let stopMergeKey = "mvk_pref_stop_merge"
    static let stopMergeItems: [StopMergeItem] = [
        StopMergeItem(id: .all, label: "Összevonva", hint: "Egy megálló, és minden járat, ami ott megáll MVK és Volán együtt."),
        StopMergeItem(id: .mvk, label: "Csak MVK", hint: "A közös megállókban csak az MVK járatai látszanak."),
        StopMergeItem(id: .coach, label: "Csak Volán", hint: "A közös megállókban csak a Volán-buszok látszanak."),
        StopMergeItem(id: .off, label: "Külön", hint: "Az MVK- és a Volán-megálló külön, ahogy a menetrendben szerepel."),
    ]

    // MARK: - Megállófigyelő features

    static let predictedVehicleKey = "mvk_pref_predicted_vehicle"

    static let watchFeatures: [PrefItem] = [
        PrefItem(id: "catch", key: "mvk_pref_watch_catch", label: "„Elérem?” indulj most", hint: "A következő indulásnál: a helyzetedből mikor indulj el, hogy elérd, és a „Szólj” gomb."),
        PrefItem(id: "leaveTimes", key: "mvk_pref_watch_leave_times", label: "Indulási idők a sorokban", hint: "Minden indulás mellett az idő, amikorra el kell indulnod hozzá."),
        PrefItem(id: "startRisk", key: "mvk_pref_watch_start_risk", label: "Késve indulás előrejelzése", hint: "Ha a menet busza még az előző menetén késik még mielőtt az MVK kihúzná."),
        PrefItem(id: "traffic", key: "mvk_pref_watch_traffic", label: "Dugó a busz előtt", hint: "Ha az ide tartó busz előtt beállt a forgalom, mennyi pluszidőt hoz."),
        PrefItem(id: "forecast", key: "mvk_pref_watch_forecast", label: "„Legrosszabb esetben” becslés", hint: "A következő busz várható legnagyobb késése ennél a megállónál."),
        PrefItem(id: "predictedVehicle", key: predictedVehicleKey, label: "Rendszám-előrejelzés", hint: "Mielőtt a busz élőben megjelenne, a várható rendszámát ~ jellel mutatjuk a korábbi fordák alapján. Ahol a busz a végállomáson visszafordul, ott ~ nélkül: azt már tudjuk."),
        PrefItem(id: "replacement", key: "mvk_pref_watch_replacement", label: "Kihúzott menet helyett", hint: "A törölt menet mellett, mikor jön helyette a következő ugyanazzal a vonallal."),
        PrefItem(id: "vehicleTrack", key: "mvk_pref_watch_vehicle_track", label: "A következő busz doboza", hint: "Jármű, sebesség, hol jár most, és követés a térképen."),
        PrefItem(id: "commute", key: "mvk_pref_watch_commute", label: "„Szokásos utad” kártya", hint: "Az utazásnaplódból felismert rendszeres út a Figyelő tetején, a szokásos idő előtt."),
    ]

    static let tabBadgesKey = "mvk_pref_tab_badges"
    static let headerPrefs: [PrefItem] = [
        PrefItem(id: "tabBadges", key: tabBadgesKey, label: "Számlálók a füleken", hint: "A Figyelő fülön a figyelt megállók száma, a Statisztikán az élő zavarok jelzése."),
    ]
}

@MainActor
extension LocalStore {

    /// The enabled modes; at least one always stays (`useEnabledModes`).
    var enabledModes: [TransitMode] {
        let on = Preferences.modeItems.filter { bool($0.key) }.map(\.id)
        return on.isEmpty ? [.tram, .bus] : on
    }

    var modesParam: String { TransitModes.param(enabledModes) }

    var stopMerge: StopMerge {
        json(Preferences.stopMergeKey, as: String.self).flatMap(StopMerge.init(rawValue:)) ?? .all
    }

    func setStopMerge(_ merge: StopMerge) {
        setJSON(Preferences.stopMergeKey, merge.rawValue)
    }

    var boardKey: String { TransitModes.boardKey(enabledModes, merge: stopMerge) }

    func feature(_ id: String) -> Bool {
        guard let item = Preferences.watchFeatures.first(where: { $0.id == id }) else { return true }
        return bool(item.key)
    }

    var showsTabBadges: Bool { bool(Preferences.tabBadgesKey) }
}
