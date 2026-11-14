//
//  SettingsSheet.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI
import UIKit

/// Beállítások (web `SettingsMenu`): transport modes, the Megállófigyelő
/// features, the header counters, location, and the account row — then what
/// only the iPhone has.
struct SettingsSheet: View {
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var location: LocationProvider
    @ObservedObject private var local = LocalStore.shared
    @State private var signedIn = AccountSession.current != nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // Like the web panel, the header and the account row stay put
            // while the long list scrolls between them.
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 0) {
                        modesGroup
                        separator
                        group("Megállófigyelő", items: Preferences.watchFeatures)
                        separator
                        group("Fejléc", items: Preferences.headerPrefs)
                        locationRow
                        separator
                        deviceRow
                    }
                    .padding(.bottom, 8)
                }
                accountRow
                    .overlay(alignment: .top) { separator }
            }
            .background(Theme.popover)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .onReceive(NotificationCenter.default.publisher(for: .mvkSessionChange)) { _ in
            signedIn = AccountSession.current != nil
        }
    }

    private var separator: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Beállítások")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                HStack(spacing: 6) {
                    Image(systemName: signedIn ? "icloud" : "icloud.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(signedIn ? Theme.primary : Theme.mutedForeground)
                    Text(signedIn ? "Felhőbe szinkronizálva, minden eszközödön ugyanígy." : "Ezen az eszközön. Bejelentkezve a felhőbe is szinkronizáljuk.")
                        .font(Theme.sans(11))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 44)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { separator }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.sans(10.5, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(Theme.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func toggleRow(label: String, hint: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Text(hint)
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineSpacing(1.3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MVKSwitch(isOn: isOn, label: label)
                .padding(.top, 2)
                .disabled(disabled)
                .opacity(disabled ? 0.5 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if !disabled { isOn.wrappedValue.toggle() } }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Groups

    /// What shows on the map, in the watchlist, the timetable, the planner
    /// and the statistics. One mode always stays on.
    private var modesGroup: some View {
        let enabled = local.enabledModes
        return VStack(spacing: 0) {
            groupTitle("Közlekedési módok")
            ForEach(Preferences.modeItems) { item in
                let isLast = enabled.count == 1 && enabled[0] == item.id
                toggleRow(
                    label: item.label,
                    hint: isLast ? "Legalább egy mód bekapcsolva marad." : item.hint,
                    isOn: local.boolBinding(item.key),
                    disabled: isLast
                )
            }
            if enabled.contains(.coach), enabled.contains(.tram) || enabled.contains(.bus) {
                stopMergeRow
            }
        }
        .padding(6)
    }

    /// A shared stop (MVK pole and Volán stop at the same place): one stop
    /// with both operators' runs, only one of them, or separate.
    private var stopMergeRow: some View {
        let merge = local.stopMerge
        let current = Preferences.stopMergeItems.first { $0.id == merge } ?? Preferences.stopMergeItems[0]
        return VStack(alignment: .leading, spacing: 6) {
            Text("Közös megállók")
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            HStack(spacing: 4) {
                ForEach(Preferences.stopMergeItems) { item in
                    let isOn = merge == item.id
                    Button { local.setStopMerge(item.id) } label: {
                        Text(item.label)
                            .font(Theme.sans(11, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(isOn ? Theme.primaryForeground : Theme.mutedForeground)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .padding(.horizontal, 4)
                            .background(isOn ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                            .mvkShadow(isOn ? Theme.Shadow.sm : Theme.Shadow.none)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Theme.muted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            Text(current.hint)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func group(_ title: String, items: [PrefItem]) -> some View {
        VStack(spacing: 0) {
            groupTitle(title)
            ForEach(items) { item in
                toggleRow(label: item.label, hint: item.hint, isOn: local.boolBinding(item.key))
            }
        }
        .padding(6)
    }

    /// Location on/off (per device; the position never goes to the cloud).
    private var locationRow: some View {
        let isOn = location.status == .watching || location.status == .requesting
        return VStack(spacing: 0) {
            groupTitle("Helyzet")
            toggleRow(
                label: "Helymeghatározás",
                hint: location.status == .denied
                    ? "Az iOS letiltotta ehhez az apphoz. A Beállítások appban engedélyezheted."
                    : "Ebből számoljuk a sétát, az „Elérem?”-et és a felszállás felismerését. Csak ezen az eszközön marad.",
                isOn: Binding(get: { isOn }, set: { $0 ? location.start() : location.stop() }),
                disabled: location.status == .denied || location.status == .unavailable
            )
            if location.status == .denied {
                Button("Beállítások megnyitása") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.mvk(.outline, size: .small))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .padding(6)
    }

    private var accountRow: some View {
        navRow(icon: "person", title: "Fiók és felhős mentés", subtitle: "Kedvencek és beállítások szinkronizálása") {
            dismiss()
            navigation.isAccountOpen = true
        }
        .padding(6)
    }

    private var deviceRow: some View {
        NavigationLink {
            DeviceSettingsScreen()
        } label: {
            rowLabel(icon: "iphone", title: "Ezen az iPhone-on", subtitle: "Offline menetrend, óra és widget, alaptérkép, névjegy")
        }
        .buttonStyle(.plain)
        .padding(6)
    }

    private func navRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Text(subtitle)
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.mutedForeground)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
