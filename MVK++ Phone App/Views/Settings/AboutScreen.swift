//
//  AboutScreen.swift
//  MVK++ Phone App
//

import SwiftUI

/// "Névjegy" — everything about the app itself that nobody needs on every
/// visit to Settings: which server it talks to, which GTFS release is
/// loaded, the app version, and where the map tiles come from.
struct AboutScreen: View {

    @EnvironmentObject private var store: TransitStore
    @State private var isReloadingStops = false

    var body: some View {
        Form {
            appSection
            serverSection
            attributionSection
        }
        .mvkBackground()
        .navigationTitle("Névjegy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appSection: some View {
        Section {
            LabeledContent("Verzió", value: appVersion)
        }
        .listRowBackground(Theme.card)
    }

    private var serverSection: some View {
        Section {
            LabeledContent("Cím") {
                Text(APIConfig.baseURLString)
                    .font(Theme.mono(12, weight: .regular))
                    .foregroundStyle(Theme.mutedForeground)
            }

            if let meta = store.gtfsMeta {
                LabeledContent("Menetrendi kiadás") {
                    Text(meta.feedVersion)
                        .font(Theme.mono(12, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                }
                LabeledContent("Megállók", value: "\(meta.stops)")
                LabeledContent("Járatok", value: "\(meta.routes)")
            }

            Button {
                Task {
                    isReloadingStops = true
                    await store.loadStatic()
                    isReloadingStops = false
                }
            } label: {
                if isReloadingStops {
                    ProgressView().tint(Theme.primary)
                } else {
                    Label("Menetrend frissítése", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isReloadingStops)
        } header: {
            Label("Szerver", systemImage: "server.rack")
        }
        .listRowBackground(Theme.card)
    }

    private var attributionSection: some View {
        Section {
            ForEach(mapAttributions, id: \.self) { line in
                Text(line)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mutedForeground)
            }
        } header: {
            Label("Térképadatok", systemImage: "map")
        }
        .listRowBackground(Theme.card)
    }

    /// Distinct attribution lines across every tile source, in catalog order.
    private var mapAttributions: [String] {
        var seen: Set<String> = []
        return TileLayerCatalog.all
            .map(\.attribution)
            .filter { seen.insert($0).inserted }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
