//
//  OfflineMapSettingsView.swift
//  MVK++ Phone App
//

import SwiftUI

/// "Térkép letöltése" — the offline pack manager.
struct OfflineMapSettingsView: View {

    @ObservedObject private var manager = OfflineMapManager.shared
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        Form {
            scopeSection
            sourcesSection
        }
        .mvkBackground()
        .navigationTitle("Térkép letöltése")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - What to download

    private var scopeSection: some View {
        Section {
            Picker("Terület", selection: $manager.selectedAreaId) {
                ForEach(OfflineArea.all) { area in
                    Text(area.name).tag(area.id)
                }
            }
            .pickerStyle(.navigationLink)
            .tint(Theme.primary)

            Picker("Részletesség", selection: $manager.selectedDetail) {
                ForEach(OfflineDetail.allCases) { detail in
                    Text(detail.name).tag(detail)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Becsült méret") {
                Text("kb. \(byteText(manager.estimatedBytes())) · \(manager.estimatedTileCount().formatted()) csempe")
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }
        } header: {
            Label("Mit töltsön le", systemImage: "square.dashed")
        } footer: {
            Text("Wifin ajánlott.")
        }
        .listRowBackground(Theme.card)
        .disabled(manager.isDownloading)
    }

    // MARK: - One row per tile source

    private var sourcesSection: some View {
        Section {
            ForEach(TileLayerCatalog.downloadableSources) { option in
                sourceRow(option)
            }
        } header: {
            Label("Alaptérképek", systemImage: "square.3.layers.3d")
        } footer: {
            if let message = manager.errorMessage {
                Text(message).foregroundStyle(Theme.destructive)
            } else {
                Text("Egy letöltés a hasonló nézeteket is lefedi.")
            }
        }
        .listRowBackground(Theme.card)
    }

    private func sourceRow(_ option: TileLayerOption) -> some View {
        let pack = manager.pack(for: option.sourceId)
        let covered = TileLayerCatalog.layers(source: option.sourceId)
        let isActive = manager.progress?.sourceId == option.sourceId

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.hex(option.swatch, fallback: Theme.muted))
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(pack != nil ? Theme.primary : Theme.border, lineWidth: pack != nil ? 2 : 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(covered.map(\.name).joined(separator: " · "))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text(packSummary(pack))
                        .font(.system(size: 11))
                        .foregroundStyle(pack != nil ? Theme.primary : Theme.mutedForeground)
                }

                Spacer(minLength: 8)

                if isActive {
                    Button("Mégse") { manager.cancelDownload() }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.destructive)
                } else {
                    Button(pack == nil ? "Letöltés" : "Frissítés") {
                        manager.download(option)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.primary)
                    .disabled(manager.isDownloading)
                }
            }

            if isActive, let progress = manager.progress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction)
                        .tint(Theme.primary)
                    Text("\(progress.completed.formatted()) / \(progress.total.formatted()) csempe")
                        .font(Theme.mono(10, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }

            if pack != nil, !isActive {
                Button(role: .destructive) {
                    manager.delete(option)
                } label: {
                    Label("Letöltés törlése", systemImage: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func packSummary(_ pack: OfflinePack?) -> String {
        guard let pack else { return "Nincs letöltve" }
        let area = OfflineArea.area(id: pack.areaId).name
        let detail = OfflineDetail(rawValue: pack.detail)?.name ?? pack.detail
        return "\(area) · \(detail) · \(byteText(pack.bytes)) · \(pack.downloadedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
