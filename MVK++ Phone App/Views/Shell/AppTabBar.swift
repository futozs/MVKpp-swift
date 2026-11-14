//
//  AppTabBar.swift
//  MVK++ Phone App
//

import Combine
import SwiftUI

/// One of the six views (web `navTabs.tsx`).
struct NavTab: Identifiable {
    let id: AppTab
    /// The full name — for VoiceOver.
    let label: String
    /// The short name under the icon.
    let short: String
    let icon: String

    static let all: [NavTab] = [
        NavTab(id: .map, label: "Forgalmi térkép", short: "Térkép", icon: "map"),
        NavTab(id: .multistop, label: "Megállófigyelő", short: "Figyelő", icon: "dot.radiowaves.left.and.right"),
        NavTab(id: .timetable, label: "Menetrend", short: "Menetrend", icon: "calendar.badge.clock"),
        NavTab(id: .parking, label: "Parkoló", short: "Parkoló", icon: "parkingsign.square"),
        NavTab(id: .planner, label: "Útvonaltervező", short: "Útvonal", icon: "point.topleft.down.to.point.bottomright.curvepath"),
        NavTab(id: .stats, label: "Statisztika", short: "Statisztika", icon: "chart.bar"),
    ]
}

struct TabCounts {
    var monitoredStops: Int
    var liveIncidents: Int

    enum Kind { case monitored, incident }

    /// Which tab shows which counter (when there is anything to show).
    func badge(for tab: AppTab) -> (kind: Kind, value: Int)? {
        if tab == .multistop, monitoredStops > 0 { return (.monitored, monitoredStops) }
        if tab == .stats, liveIncidents > 0 { return (.incident, liveIncidents) }
        return nil
    }
}

/// The views at the bottom, under the thumb: six equal columns on a Liquid
/// Glass bar, a soft pill behind the active icon (web `MobileTabBar`). Drawn
/// here because the system tab bar folds a sixth tab into "More".
struct AppTabBar: View {
    @Binding var selection: AppTab
    let counts: TabCounts
    let showBadges: Bool

    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NavTab.all) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 60)
        .glassEffect(.regular.tint(Theme.glassTint), in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private func item(_ tab: NavTab) -> some View {
        let isActive = selection == tab.id
        let badge = showBadges ? counts.badge(for: tab.id) : nil
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) { selection = tab.id }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isActive {
                        Capsule()
                            .fill(Theme.primary.opacity(0.2))
                            .matchedGeometryEffect(id: "indicator", in: indicator)
                    }
                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Theme.primary : Theme.mutedForeground)
                        .overlay(alignment: .topTrailing) {
                            if let badge { TabBadge(kind: badge.kind, value: badge.value).offset(x: 10, y: -6) }
                        }
                }
                .frame(width: 48, height: 28)
                Text(tab.short)
                    .font(Theme.sans(10.5, weight: isActive ? .semibold : .medium))
                    .tracking(-0.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isActive ? Theme.foreground : Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label + (badge.map { badgeText($0.kind, $0.value) } ?? ""))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func badgeText(_ kind: TabCounts.Kind, _ value: Int) -> String {
        kind == .incident ? ", \(value) élő üzemzavar-jelzés" : ", \(value) figyelt megálló"
    }
}

/// The counter on a tab. Colour carries meaning: green is your own watch,
/// red a live disruption.
struct TabBadge: View {
    let kind: TabCounts.Kind
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(Theme.mono(9.5, weight: .bold))
            .foregroundStyle(kind == .incident ? Theme.destructiveForeground : Theme.primaryForeground)
            .padding(.horizontal, 3)
            .frame(minWidth: 16, minHeight: 16)
            .background(kind == .incident ? Theme.late : Theme.primary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.background, lineWidth: 2).padding(-2))
            .fixedSize()
            .accessibilityHidden(true)
    }
}
