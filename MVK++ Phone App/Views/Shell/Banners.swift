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
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                        Text("Betöltés").font(Theme.sans(12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.primaryForeground)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Theme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.primary.opacity(0.30), lineWidth: 1))
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
                Image(systemName: "train.side.front.car")
                    .font(.system(size: 14))
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
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(Theme.primary.opacity(0.25), lineWidth: 1))
            .glassEffect(.regular.tint(Theme.glassTint), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Új: vonatok és Volán-buszok")
        }
    }
}
