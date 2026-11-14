//
//  Banners.swift
//  MVK++ Phone App
//

import SwiftUI

/// A setting changed on another device has arrived — one tap loads it
/// (web `SyncBanner`).
struct SyncBanner: View {
    @ObservedObject private var sync = CloudSync.shared

    var body: some View {
        if sync.pendingRemote {
            HStack(spacing: 12) {
                Text("Egy másik eszközön módosítottad a beállításaidat.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    sync.pendingRemote = false
                    AppReloader.shared.reload()
                } label: {
                    Label("Betöltés", systemImage: "arrow.clockwise")
                        .font(Theme.sans(12, weight: .semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Theme.primaryForeground)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .glassEffect(.regular.tint(Theme.glassTint), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
        }
    }
}

/// One-time card: Volán and rail are on by default — keep them with one tap,
/// or go back to MVK only. The decision (and the modes) sync, so other
/// devices do not ask again (web `RegionalIntroBanner`).
struct RegionalIntroBanner: View {
    @ObservedObject private var local = LocalStore.shared

    var body: some View {
        if local.string(Preferences.regionalIntroKey) == nil {
            HStack(spacing: 12) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36)
                    .background(Theme.primary.opacity(0.2), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Új: vonatok és Volán-buszok is")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text("Borsod-Abaúj-Zemplénben a térképen, a figyelőben (vasútállomás, vágány, késés oka) és a menetrendben. A Beállításokban módonként kikapcsolhatod.")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    Button("Maradjon") { local.setJSON(Preferences.regionalIntroKey, "all") }
                        .buttonStyle(.mvk(.primary, size: .small))
                    Button("Csak MVK") {
                        local.setBool(Preferences.modeItems[2].key, false)
                        local.setBool(Preferences.modeItems[3].key, false)
                        local.setJSON(Preferences.regionalIntroKey, "mvk")
                    }
                    .buttonStyle(.mvk(.ghost, size: .small))
                }
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .glassEffect(.regular.tint(Theme.glassTint), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Új: vonatok és Volán-buszok")
        }
    }
}
