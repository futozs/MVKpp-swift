//
//  MapLayersMenu.swift
//  MVK++ Phone App
//

import SwiftUI

/// „Térkép” (top right): the base map and the layers in one place
/// (`controls/MapLayersControl.tsx`). Layers do not filter, they only change
/// what is drawn.
struct MapLayersMenu: View {
    @Binding var tileLayerId: String
    @Binding var filters: FilterState
    let watchedStops: Int

    private struct Toggle: Identifiable {
        let key: WritableKeyPath<FilterState, Bool>
        let label: String
        let hint: String?
        var disabled = false
        var traffic = false
        var id: String { label }
    }

    private var toggles: [Toggle] {
        [
            Toggle(key: \.traffic, label: "Forgalom (dugók)", hint: "élőben, a buszok menetidejéből", traffic: true),
            Toggle(key: \.others, label: "Többi busz követéskor", hint: "utazás közben is, halványan"),
            Toggle(key: \.stops, label: "Megállók", hint: nil),
            Toggle(key: \.onlyWatched, label: "Csak a figyelt megállók", hint: "\(watchedStops) figyelt", disabled: !filters.stops),
            Toggle(key: \.shape, label: "Járatok nyomvonala", hint: "a kiválasztott járatoké"),
            Toggle(key: \.labels, label: "Rendszám a buszokon", hint: nil),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Alaptérkép")
            HStack(spacing: 6) {
                ForEach(TileLayerCatalog.all) { layer in
                    let on = layer.id == tileLayerId
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        tileLayerId = layer.id
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                .fill(Theme.hex(layer.swatch, fallback: Theme.muted))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                        .strokeBorder(on ? Theme.primary : Theme.border, lineWidth: 2)
                                )
                                .mvkShadow(Theme.Shadow.sm)
                                .overlay {
                                    if on {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Theme.primaryForeground)
                                            .frame(width: 16, height: 16)
                                            .background(Theme.primary, in: Circle())
                                    }
                                }
                            Text(layer.short)
                                .font(Theme.sans(10, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Theme.foreground : Theme.mutedForeground)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(layer.name), \(layer.note)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 8)

            heading("Rétegek").padding(.top, 12)
            VStack(spacing: 0) {
                ForEach(toggles) { t in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.label)
                                .font(Theme.sans(13, weight: .medium))
                                .foregroundStyle(Theme.foreground)
                            if let hint = t.hint {
                                Text(hint)
                                    .font(Theme.sans(11))
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                            if t.traffic {
                                HStack(spacing: 6) {
                                    Text("lassul")
                                    Capsule()
                                        .fill(LinearGradient(colors: [TrafficColor.color(0), TrafficColor.color(0.5), TrafficColor.color(1)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: 80, height: 6)
                                    Text("beállt")
                                }
                                .font(Theme.sans(10))
                                .foregroundStyle(Theme.mutedForeground)
                                .padding(.top, 3)
                                .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        MVKSwitch(isOn: Binding(get: { filters[keyPath: t.key] }, set: { filters[keyPath: t.key] = $0 }), label: t.label)
                    }
                    .disabled(t.disabled)
                    .opacity(t.disabled ? 0.5 : 1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(width: 300)
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.sans(11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Theme.mutedForeground)
            .padding(.horizontal, 4)
    }
}
