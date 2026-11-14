//
//  OfflineScheduleSettingsView.swift
//  MVK++ Phone App
//

import SwiftUI

/// "Menetrend letöltése" — the offline timetable manager.
struct OfflineScheduleSettingsView: View {

    @EnvironmentObject private var store: TransitStore
    @ObservedObject private var manager = OfflineScheduleManager.shared

    var body: some View {
        Form {
            scopeSection
            actionSection
        }
        .mvkBackground()
        .navigationTitle("Menetrend letöltése")
        .navigationBarTitleDisplayMode(.inline)
        .task { await manager.refreshBytes() }
    }

    // MARK: - How much to keep

    private var scopeSection: some View {
        Section {
            Picker("Időtáv", selection: $manager.scope) {
                ForEach(OfflineScheduleScope.allCases) { scope in
                    Text(scope.name).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Automatikus letöltés", isOn: $manager.autoDownloadEnabled)
                .tint(Theme.primary)
        } footer: {
            Text(statusText)
        }
        .listRowBackground(Theme.card)
        .disabled(manager.isDownloading)
    }

    private var statusText: String {
        guard !manager.manifest.isEmpty else { return "Még nincs letöltve." }
        let days = manager.manifest.days.count
        let size = byteText(manager.bytes)
        guard isCurrentRelease else {
            return "\(days) nap letöltve, \(size). Új menetrendi kiadás jelent meg, érdemes frissíteni."
        }
        return "\(days) nap letöltve, \(size)."
    }

    /// The stored pack was built from the release the gateway still serves.
    /// A new release moves departure times, so a stale pack is not merely old.
    private var isCurrentRelease: Bool {
        manager.isCurrent(feedVersion: store.gtfsMeta?.feedVersion)
    }

    // MARK: - Download

    private var actionSection: some View {
        Section {
            if let progress = manager.progress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress.fraction)
                        .tint(Theme.primary)
                    Text("\(progress.dayNumber). nap / \(progress.dayCount)")
                        .font(Theme.mono(11, weight: .regular))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .padding(.vertical, 2)

                Button(role: .destructive) {
                    manager.cancelDownload()
                } label: {
                    Label("Mégse", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    manager.startDownload(meta: store.gtfsMeta)
                } label: {
                    Label(
                        manager.manifest.isEmpty ? "Menetrend letöltése" : "Frissítés",
                        systemImage: "arrow.down.circle"
                    )
                }

                if !manager.manifest.isEmpty {
                    Button(role: .destructive) {
                        manager.deleteAll()
                    } label: {
                        Label("Letöltés törlése", systemImage: "trash")
                    }
                }
            }
        } footer: {
            if let message = manager.errorMessage {
                Text(message).foregroundStyle(Theme.destructive)
            }
        }
        .listRowBackground(Theme.card)
    }

    private func byteText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
