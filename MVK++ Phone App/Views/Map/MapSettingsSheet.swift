//
//  MapSettingsSheet.swift
//  MVK++ Phone App
//

import SwiftUI

/// The base map choices, exactly the web app's five: street, dark, faded,
/// satellite and topographic.
///
/// Three of them are the same OpenStreetMap tiles under different colour
/// treatments, so each row leads with a swatch — the names alone ("Sötét",
/// "Halvány") would not tell them apart.
struct BaseMapList: View {
    @Binding var selectedLayerId: String
    /// Called after a pick, so a sheet can close itself.
    var onSelect: (() -> Void)?

    var body: some View {
        List(TileLayerCatalog.all) { layer in
            let selected = layer.id == selectedLayerId

            Button {
                selectedLayerId = layer.id
                onSelect?()
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.hex(layer.swatch, fallback: Theme.muted))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                .strokeBorder(selected ? Theme.primary : Theme.border, lineWidth: selected ? 2 : 1)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.name)
                            .font(.system(size: 15, weight: selected ? .semibold : .medium))
                            .foregroundStyle(Theme.foreground)
                        Text(layer.note)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.mutedForeground)
                    }

                    Spacer(minLength: 8)

                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.primaryForeground)
                            .frame(width: 24, height: 24)
                            .background(Theme.primary, in: Circle())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(selected ? Theme.primary.opacity(0.10) : Color.clear)
            .listRowSeparatorTint(Theme.border)
        }
        .listStyle(.plain)
        .mvkBackground()
        .safeAreaInset(edge: .bottom) {
            // Both OpenStreetMap and Esri require visible attribution.
            Text(TileLayerCatalog.layer(id: selectedLayerId).attribution)
                .font(.system(size: 10))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}

/// The picker as reached from the map's control panel.
struct MapSettingsSheet: View {
    @Binding var selectedLayerId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BaseMapList(selectedLayerId: $selectedLayerId) { dismiss() }
                .navigationTitle("Alaptérkép")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kész") { dismiss() }
                    }
                }
        }
    }
}
