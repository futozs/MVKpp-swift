//
//  StatsScreen.swift
//  MVK++ Phone App
//

import SwiftUI

/// The Statistika tab (web `StatsView.tsx`): a scrolling row of panels and
/// the Áttekintés button on the right, the chosen panel below.
struct StatsScreen: View {
    enum Panel: String, CaseIterable, Identifiable {
        case overview, vehicle, incident, route, stop, network, heat, regional

        var id: String { rawValue }

        var label: String {
            switch self {
            case .overview: return "Áttekintés"
            case .vehicle: return "Járművek"
            case .incident: return "Zavarok"
            case .route: return "Vonalak"
            case .stop: return "Megállók"
            case .network: return "Hálózat"
            case .heat: return "Hőtérkép"
            case .regional: return "Vasút"
            }
        }

        var icon: String {
            switch self {
            case .overview: return "waveform.path.ecg"
            case .vehicle: return "bus"
            case .incident: return "wrench"
            case .route: return "point.topleft.down.to.point.bottomright.curvepath"
            case .stop: return "mappin.and.ellipse"
            case .network: return "chart.line.uptrend.xyaxis"
            case .heat: return "flame"
            case .regional: return "train.side.front.car"
            }
        }
    }

    @EnvironmentObject private var store: TransitStore
    @ObservedObject private var local = LocalStore.shared

    /// nil until the live incident count decides the first panel: with a
    /// live disruption the Üzemzavarok panel opens first.
    @State private var panel: Panel?

    private var modes: [TransitMode] { local.enabledModes }
    private var regional: Bool { TransitModes.hasRegional(modes) }

    private var panels: [Panel] {
        let base: [Panel] = [.vehicle, .incident, .route, .stop, .network, .heat]
        return regional ? base + [.regional] : base
    }

    /// Incidents and heat belong to the MVK network; there is no such
    /// measurement for the regional feeds.
    private var mvkRoutes: [Route] {
        store.routes.values
            .filter { !TransitModes.isRegionalId($0.id) }
            .sorted { $0.short.localizedStandardCompare($1.short) == .orderedAscending }
    }

    private var allRoutes: [Route] {
        store.routes.values.sorted { $0.short.localizedStandardCompare($1.short) == .orderedAscending }
    }

    var body: some View {
        let current = panel ?? .vehicle
        VStack(spacing: 0) {
            nav(current)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content(current)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.immediately)
            .safeAreaPadding(.bottom, 90)
        }
        .background(Theme.background)
        .task {
            guard panel == nil else { return }
            let live = try? await APIClient.shared.liveIncidents()
            if panel == nil { panel = (live?.missing.isEmpty == false) ? .incident : .vehicle }
        }
        .onChange(of: regional) { _, isOn in
            if !isOn, panel == .regional { panel = .vehicle }
        }
    }

    @ViewBuilder
    private func content(_ current: Panel) -> some View {
        switch current {
        case .overview: StatsOverviewPanel(onJumpToVehicles: { panel = .vehicle })
        case .vehicle: StatsVehiclePanel(routes: allRoutes)
        case .incident: StatsIncidentPanel(routes: mvkRoutes)
        case .route: StatsRoutePanel(routes: allRoutes)
        case .stop: StatsStopPanel(stops: store.stops)
        case .network: StatsNetworkPanel()
        case .heat: StatsHeatPanel(routes: mvkRoutes)
        case .regional:
            if regional { StatsRegionalPanel(modes: modes) }
        }
    }

    private func nav(_ current: Panel) -> some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(panels) { p in
                            navButton(p, active: current == p)
                                .id(p)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.trailing, 24)
                }
                .mask {
                    LinearGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .onChange(of: current) { _, p in
                    withAnimation(Theme.Motion.normalAnimation) { proxy.scrollTo(p, anchor: .center) }
                }
            }

            Button {
                panel = .overview
            } label: {
                Image(systemName: Panel.overview.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(current == .overview ? Theme.primaryForeground : Theme.mutedForeground)
                    .frame(width: 34, height: 30)
                    .background(current == .overview ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).strokeBorder(current == .overview ? Theme.primary : Theme.border.opacity(0.7), lineWidth: 1))
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Áttekintés: rendszám-jóslás pontossága és adatraktár")
        }
        .padding(.horizontal, 12)
        .background(Theme.background.opacity(0.85))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func navButton(_ p: Panel, active: Bool) -> some View {
        Button {
            panel = p
        } label: {
            HStack(spacing: 6) {
                Image(systemName: p.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(p.label)
                    .font(Theme.sans(12, weight: .semibold))
            }
            .foregroundStyle(active ? Theme.primaryForeground : Theme.mutedForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(active ? Theme.primary : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
