//
//  WatchSettingsView.swift
//  MVK++ Watch App
//

import SwiftUI
import WidgetKit

/// The watch's own switches, and the phone's settings it follows. Anything
/// changed here goes back to the phone, so the rider never sets it twice.
struct WatchSettingsView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var catalog: StopsCatalog
    @EnvironmentObject private var link: WatchLink
    @EnvironmentObject private var rides: RideController

    var body: some View {
        List {
            Section("Figyelő") {
                Toggle("Legközelebbi elöl", isOn: $favorites.nearestFirstEnabled)
            }

            Section {
                Toggle("Legközelebbi figyelt megálló", isOn: $favorites.widgetNearestEnabled)
                Picker("Megálló", selection: $favorites.widgetStopId) {
                    Text("Az első figyelt").tag(String?.none)
                    ForEach(favorites.stopIds, id: \.self) { stopId in
                        Text(name(of: stopId)).tag(String?.some(stopId))
                    }
                }
                .disabled(favorites.widgetNearestEnabled)
            } header: {
                Text("Számlap és Smart Stack")
            } footer: {
                Text("A következő indulás ennél a megállónál látszik. A telefonon is állítható.")
            }

            Section {
                Toggle("Rezgés utazás közben", isOn: Binding(get: { rides.hapticsEnabled }, set: { rides.hapticsEnabled = $0 }))
            } footer: {
                Text("Minden megállónál egy koppintás, a leszállás előtt erős jelzés.")
            }

            Section {
                LabeledContent("Járművek", value: link.settings.modes.map(modeLabel).joined(separator: ", "))
                LabeledContent("Közös megállók", value: mergeLabel)
                LabeledContent("Kedvenc vonalak", value: "\(link.settings.lineFavorites.count)")
            } header: {
                Text("A telefonról")
            } footer: {
                Text("Az MVK++ telefonos beállításaiban módosíthatod.")
            }

            Section("Kapcsolat") {
                LabeledContent("Telefon", value: link.isReachable ? "Elérhető" : "Nem elérhető")
                if let synced = link.lastSyncAt {
                    LabeledContent("Utolsó szinkron") {
                        Text(synced, style: .time)
                    }
                }
                LabeledContent("Élő adat", value: RealtimeClient.shared.connected ? "WebSocket" : "Lekérdezés")
            }
        }
        .navigationTitle("Beállítások")
        .onChange(of: favorites.widgetStopId) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
    }

    private func name(of stopId: String) -> String {
        catalog.stops.first { $0.id == stopId }?.name ?? stopId
    }

    private func modeLabel(_ mode: TransitMode) -> String {
        switch mode {
        case .tram: return "villamos"
        case .bus: return "busz"
        case .coach: return "Volán"
        case .rail: return "vonat"
        }
    }

    private var mergeLabel: String {
        switch link.settings.merge {
        case .all: return "Összevonva"
        case .mvk: return "Csak MVK"
        case .coach: return "Csak Volán"
        case .off: return "Külön"
        }
    }
}
